const std = @import("std");
const types = @import("types.zig");
const images = @import("images.zig");
const lines = @import("lines.zig");
const triangles = @import("triangles.zig");
const transform_ui = @import("transform_ui.zig");
const zigar = @import("zigar");
const shapes = @import("shapes/shapes.zig");
const rects = @import("rects.zig");
const bounding_box = @import("shapes/bounding_box.zig");
const shared = @import("shared.zig");
const texture_size = @import("texture_size.zig");
const utils = @import("utils.zig");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const path_utils = @import("shapes/path_utils.zig");
const consts = @import("consts.zig");
const UI = @import("ui.zig");
const texts = @import("texts/texts.zig");
const sdf_drawing = @import("sdf/drawing.zig");
const fonts = @import("texts/fonts.zig");
const AssetId = @import("asset_id.zig").AssetId;
const Asset = @import("types.zig").Asset;
const AssetSerialized = @import("types.zig").AssetSerialized;
const asset_props = @import("asset_props.zig");
const snapshots = @import("snapshots.zig");
const ActionType = @import("types.zig").ActionType;
const Tool = @import("types.zig").Tool;
const typography_props = @import("texts/typography_props.zig");
const js_glue = @import("js_glue.zig");
const sdf_effect = @import("sdf/effect.zig");
const caret = @import("texts/caret.zig");

const FillType = enum(u8) {
    Solid,
    LinearGradient,
    RadialGradient,
};

const Placement = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

const WebGpuPrograms = struct {
    draw_texture: *const fn ([]const types.PointUV, u32) void,
    draw_triangle: *const fn ([]const triangles.DrawInstance) void,
    compute_shape: *const fn ([]const types.Point, u32, u32, u32) void,
    clear_sdf: *const fn (u32, u32, u32, u32) void,
    combine_sdf: *const fn (u32, u32, u32, Placement) void,
    draw_blur: *const fn (u32, u32, u32, u32, f32, f32) void,
    draw_shape: *const fn ([]const types.PointUV, sdf_drawing.DrawUniform, u32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const triangles.PickInstance) void,
    pick_shape: *const fn ([]const images.PickVertex, shapes.PickUniform, u32) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;

pub fn connectWebGpuPrograms(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

pub fn glueJsGeneral(
    onAssetUpdate: *const fn (snapshots.ProjectSnapshot, bool) void,
    onAssetSelection: *const fn ([4]u32) void,
    onUpdateTool: *const fn (u16) void,
    createSdfTexture: *const fn () u32,
    createDisposableComputeDepthTexture: *const fn (u32, u32) u32,
    getCharData: *const fn (u32, u21) SerializedCharDetails,
    getKerning: *const fn (u32, u21, u21) f32,
) void {
    snapshots.passSnapshot = onAssetUpdate;
    js_glue.onAssetSelection = onAssetSelection;
    js_glue.onUpdateTool = onUpdateTool;
    js_glue.createSdfTexture = createSdfTexture;
    js_glue.createDisposableComputeDepthTexture = createDisposableComputeDepthTexture;
    js_glue.getCharData = getCharData;
    js_glue.getKerning = getKerning;
}

pub const SerializedCharDetails = js_glue.SerializedCharDetails;

pub const TextCallback = fn (text: []const u8) void;
var enable_typing: *const TextCallback = undefined;
var disable_typing: *const fn () void = undefined;
var update_text_content: *const TextCallback = undefined;
var update_text_selection: *const fn (start: u32, end: u32) void = undefined;

pub fn connectTyping(
    enable: *const TextCallback,
    disable: *const fn () void,
    update_content: *const TextCallback,
    update_selection: *const fn (u32, u32) void,
) void {
    enable_typing = enable;
    disable_typing = disable;
    update_text_content = update_content;
    update_text_selection = update_selection;
}

pub const @"meta(zigar)" = struct {
    pub fn isArgumentString(comptime FT: type, comptime arg_index: usize) bool {
        _ = arg_index;
        return switch (FT) {
            TextCallback => true,
            else => false,
        };
    }

    pub fn isFieldString(comptime T: type, comptime field_name: []const u8) bool {
        _ = field_name;
        return switch (T) {
            texts.Serialized => true,
            texts.ComputeTextResult => true,
            else => false,
        };
    }
};

pub fn glueJsTextureCache(
    createCacheTexture: *const fn () u32,
    startCache: *const fn (u32, bounding_box.BoundingBox, f32, f32) void,
    endCache: *const fn () void,
) void {
    js_glue.createCacheTexture = createCacheTexture;
    js_glue.startCache = startCache;
    js_glue.endCache = endCache;
}

pub const ASSET_ID_MIN: u32 = 1000;
pub const INFINITE_DISTANCE = std.math.floatMax(f32); // purely for SDF effects
const MIN_NEW_CONTROL_POINT_DISTANCE = 10.0; // Minimum distance to consider a new control point

var state = types.State{
    .width = 0,
    .height = 0,
    .assets = undefined,
    .hovered_asset_id = AssetId{},
    .selected_asset_id = AssetId{},
    .action = ActionType.None,
    .tool = Tool.None,
    .action_pointer_offset = types.Point{ .x = 0.0, .y = 0.0 }, // indicates pointer position when action has started, useful for transformatiosn with ctrl/shift
    .init_action_bounds = undefined,
    .redraw_needed = true,
};

pub fn initState(width: f32, height: f32, texture_max_size: f32, max_buffer_size: f32) !void {
    shared.texture_max_size = texture_max_size;
    shared.max_buffer_size = max_buffer_size;
    state.width = width;
    state.height = height;
    state.redraw_needed = true;
    state.assets = std.AutoArrayHashMap(u32, Asset).init(std.heap.page_allocator);
    UI.init();
    fonts.init();
}

pub fn updateRenderScale(zoom: f32, pixel_density: f32) !void {
    state.redraw_needed = true;
    shared.render_scale = 1 / (pixel_density * zoom);
    shared.ui_scale = pixel_density / zoom;
    shared.pixel_density = pixel_density;

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
                const new_sdf_dims = sdf_drawing.getSdfTextureDims(
                    shape.bounds,
                    sdf_padding,
                    false,
                    1.0,
                );

                if (new_sdf_dims.size.w > shape.sdf_size.w + consts.EPSILON or
                    new_sdf_dims.size.h > shape.sdf_size.h + consts.EPSILON)
                {
                    shape.outdated_sdf = true;
                }
            },
            .text => |*text| {
                const text_padding = sdf_drawing.getSdfPadding(text.effects.items);
                const sdf_dims = sdf_drawing.getSdfTextureDims(
                    text.bounds,
                    text_padding,
                    true,
                    1.0,
                );
                if (sdf_dims.size.w > text.last_sdf_dim_width + consts.EPSILON) {
                    text.is_sdf_outdated = true;
                }
            },
        }
    }

    // We don't update font here because we would need to know what fonts/chars are still in use!
    // so It's better to update them in render draw
}

var next_asset_id: u32 = ASSET_ID_MIN;
fn generateId() u32 {
    const id = next_asset_id;
    next_asset_id +%= 1;
    return id;
}

fn addImage(id_or_zero: u32, points: [4]types.PointUV, texture_id: u32) !void {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const asset = Asset{
        .img = images.Image.new(id, points, texture_id),
    };
    try state.assets.put(id, asset);
    snapshots.triggerNewSnapshot(true, true);
}

fn addShape(
    id_or_zero: u32,
    paths: []const []const types.Point,
    bounds: [4]types.PointUV,
    props: asset_props.Props,
    effects: []const sdf_effect.Serialized,
    sdf_texture_id: u32,
    cache_texture_id: ?u32,
) !u32 {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const shape = try shapes.Shape.new(
        id,
        paths,
        bounds,
        props,
        effects,
        sdf_texture_id,
        cache_texture_id,
        std.heap.page_allocator,
    );
    try state.assets.put(id, Asset{ .shape = shape });

    snapshots.triggerNewSnapshot(true, true);
    return id;
}

fn addText(
    id_or_zero: u32,
    content: []const u8,
    bounds: [4]types.PointUV,
    props: asset_props.Props,
    effects: []const sdf_effect.Serialized,
    typo_props: typography_props.Serialized,
    sdf_texture_id: ?u32,
) !texts.Text {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const text = try texts.Text.new(
        std.heap.page_allocator,
        id,
        content,
        bounds,
        props,
        effects,
        typo_props,
        sdf_texture_id,
    );
    try state.assets.put(id, Asset{ .text = text });
    snapshots.triggerNewSnapshot(true, true);
    return text;
}

pub fn removeAsset() !void {
    state.redraw_needed = true;
    snapshots.triggerNewSnapshot(true, true);

    if ((state.tool == .DrawShape or state.tool == .EditShape) and state.selected_asset_id.isSec() and state.selected_asset_id.isTert()) {
        if (getSelectedShape()) |shape| {
            if (shape.paths.items.len > state.selected_asset_id.getSec()) {
                var active_path = &shape.paths.items[state.selected_asset_id.getSec()];
                const point_index = state.selected_asset_id.getTert();
                if (active_path.points.items.len > point_index) {
                    _ = active_path.points.orderedRemove(point_index);
                    // TODO: split shape into two paths if they are not connected anymore
                    // handle case when that was last point
                    return;
                }
            }
        }
    }

    _ = state.assets.orderedRemove(state.selected_asset_id.getPrim());
    try setSelectedAsset(AssetId{});
}

pub fn onUpdatePick(id: [4]u32) void {
    if (state.action != .Transform and !state.hovered_asset_id.equal(id)) {
        state.redraw_needed = true;
        state.hovered_asset_id = AssetId.fromArray(id);
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

fn getSelectedAsset() ?*types.Asset {
    return state.assets.getPtr(state.selected_asset_id.getPrim());
}

fn getSelectedImg() ?*images.Image {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => |*img| return img,
        .shape => return null,
        .text => return null,
    }
}

fn getSelectedShape() ?*shapes.Shape {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
        .text => return null,
    }
}

fn getSelectedText() ?*texts.Text {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => return null,
        .text => |*text| return text,
    }
}

fn setSelectedAsset(id: AssetId) !void {
    try commitChanges();
    state.selected_asset_id = id;
    js_glue.onAssetSelection(id.serialize());
}

pub fn updateTextContent(
    input_content: []const u8,
    selection_start: usize,
    selection_end: usize,
) !texts.ComputeTextResult {
    const option_text = getSelectedText();
    if (option_text) |text| {
        std.heap.page_allocator.free(text.content);
        text.content = try std.heap.page_allocator.dupe(u8, input_content);
        // IMPORTANT: do NOT free input_content,
        // It's owned by Zigar/JS side, so hopefully it's gonna somehow handled there
        const results = try text.computeText(selection_start, selection_end);

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, true);
        return results;
    } else {
        @panic("updateTextContent called but no text asset selected");
    }
}

fn createText(x: f32, y: f32) !texts.Text {
    const id = generateId();
    const max_width = 300.0;
    const bounds = [4]types.PointUV{
        .{ .x = x, .y = y, .u = 0.0, .v = 1.0 },
        .{ .x = x + max_width, .y = y, .u = 1.0, .v = 1.0 },
        .{ .x = x + max_width, .y = y - 1.0, .u = 1.0, .v = 0.0 },
        .{ .x = x, .y = y - 1.0, .u = 0.0, .v = 0.0 },
    };

    const effects: []const sdf_effect.Serialized = &.{
        .{
            .dist_start = INFINITE_DISTANCE,
            .dist_end = 0,
            .fill = .{ .solid = .{ 1.0, 0.0, 1.0, 1.0 } },
        },
        .{
            .dist_start = 3,
            .dist_end = 1.5,
            .fill = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
        },
        .{
            .dist_start = -6,
            .dist_end = -8,
            .fill = .{ .solid = .{ 1.0, 0.0, 0.0, 1.0 } },
        },
        .{
            .dist_start = -12,
            .dist_end = -18,
            .fill = .{ .solid = .{ 1.0, 1.0, 0.0, 1.0 } },
        },
    };

    const typo_props = typography_props.Serialized{
        .font_size = 10,
        .font_family_id = 0,
        .line_height = 1.2,
        .is_sdf_shared = true,
    };

    return try addText(
        id,
        "Type here",
        bounds,
        asset_props.Props{},
        effects,
        typo_props,
        null,
    );
}

// @param auto_select - whether to select asset on pointer down, useufl for dekstop users
pub fn onPointerDown(x: f32, y: f32) !void {
    state.redraw_needed = true;

    if (state.tool == .Text) {
        try setSelectedAsset(state.hovered_asset_id);

        const text: texts.Text = if (getSelectedText()) |text| b: {
            break :b text.*;
        } else b: {
            const new_text = try createText(x, y);
            try setSelectedAsset(AssetId{ ._prim = new_text.id });
            break :b new_text;
        };

        enable_typing(text.content);

        if (state.hovered_asset_id.isSec()) {
            state.selected_asset_id.setSec(state.hovered_asset_id.getSec());

            const caret_index = state.hovered_asset_id.getSec();
            setCaretPosition(caret_index, caret_index);
            update_text_selection(caret_index, caret_index);
        }

        state.action = .TextSelection;
    } else if (state.tool == Tool.DrawShape) {
        if (getSelectedShape() == null) {
            const props = asset_props.Props{
                .blur = .{ .x = 30, .y = 30 },
            };
            const effects: []const sdf_effect.Serialized = &.{
                .{
                    .dist_start = INFINITE_DISTANCE,
                    .dist_end = 0,
                    .fill = .{ .solid = .{ 1.0, 0.0, 1.0, 1.0 } },
                },
                .{
                    .dist_start = 26,
                    .dist_end = 24,
                    .fill = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
                },
                .{
                    .dist_start = -30,
                    .dist_end = -32,
                    .fill = .{ .solid = .{ 1.0, 0.0, 0.0, 1.0 } },
                },
            };
            const id = try addShape(
                0,
                &.{},
                consts.DEFAULT_BOUNDS,
                props,
                effects,
                js_glue.createSdfTexture(),
                if (props.blur != null) js_glue.createCacheTexture() else null,
            );
            try setSelectedAsset(AssetId{ ._prim = id });
        }

        if (getSelectedShape()) |shape| {
            try shape.addPointStart(
                std.heap.page_allocator,
                types.Point{ .x = x, .y = y },
            );
            return;
        } else {
            @panic("Selected shape asset should be present at this point");
        }
    } else {
        if (state.tool == Tool.EditShape) {
            // should not be accessible on mobile, that's why selection happens with pointer down
            if (state.hovered_asset_id.isPrim()) {
                try setSelectedAsset(state.hovered_asset_id);
            }
        }

        if (state.hovered_asset_id.getPrim() >= ASSET_ID_MIN and
            state.tool == .None and
            state.action == .None)
        {
            // This standard for desktop, not sure if gonna work well with mobile
            try setSelectedAsset(state.hovered_asset_id);
        }

        if (!state.selected_asset_id.isPrim()) {
            // No active asset, do nothing
            return;
        }

        const asset = getSelectedAsset() orelse @panic("Asset should be always selected here");
        const bounds = asset.getBounds();
        state.init_action_bounds = bounds;

        if (transform_ui.isTransformUi(state.hovered_asset_id.getPrim())) {
            state.action = .Transform;
        } else if (state.selected_asset_id.getPrim() >= ASSET_ID_MIN and
            state.selected_asset_id.getPrim() == state.hovered_asset_id.getPrim())
        {
            state.action = .Move;
            state.action_pointer_offset = types.Point{
                .x = x - bounds[0].x,
                .y = y - bounds[0].y,
            };
        }
    }
}

pub fn onPointerUp() !void {
    state.redraw_needed = true;

    if (state.tool == .None) {
        if (state.action == .None) {
            // I've commented it out because I think mobile might work
            // fine with first lcick like desktop does, to be tested
            try setSelectedAsset(state.hovered_asset_id);
        } else {
            state.action = .None;
            snapshots.triggerNewSnapshot(true, true);
        }
    } else if (state.tool == Tool.DrawShape) {
        snapshots.triggerNewSnapshot(true, true);
        if (getSelectedShape()) |shape| {
            shape.onReleasePointer();
        }
    } else if (state.tool == Tool.EditShape) {
        snapshots.triggerNewSnapshot(true, true);
        if (getSelectedShape()) |shape| {
            shape.onReleasePointer();
        }
        // to remove sec, third, quat fields
        state.selected_asset_id = AssetId{ ._prim = state.selected_asset_id.getPrim() };
    } else if (state.tool == Tool.Text) {
        state.action = .None;
    }
}

pub fn onPointerMove(x: f32, y: f32, constrained: bool, maintain_center: bool) !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            state.redraw_needed = true;
            shape.updatePointPreview(types.Point{ .x = x, .y = y });
        }
        return;
    }

    if (state.tool == Tool.Text and state.action == .TextSelection) {
        if (getSelectedText() != null) {
            if (state.hovered_asset_id.getPrim() == state.selected_asset_id.getPrim()) {
                if (state.hovered_asset_id.isSec() and state.selected_asset_id.isSec()) {
                    state.redraw_needed = true;

                    const new_caret_index = state.hovered_asset_id.getSec();
                    const curr_caret_index = state.selected_asset_id.getSec();

                    const start = @min(new_caret_index, curr_caret_index);
                    const end = @max(new_caret_index, curr_caret_index);
                    setCaretPosition(start, end);
                    update_text_selection(start, end);
                }
            }
        }
        return;
    }

    if (state.tool == Tool.EditShape) {
        if (state.selected_asset_id.isTert()) {
            if (getSelectedShape()) |shape| {
                state.redraw_needed = true;

                const matrix = Matrix3x3.getMatrixFromRectangle(shape.bounds);
                const pointer = matrix.inverse().get(types.Point{ .x = x, .y = y });

                const path = shape.paths.items[state.selected_asset_id.getSec()];
                const points = path.points.items;
                const i = state.selected_asset_id.getTert(); // point index

                if (i % 3 == 0) { // it's control point
                    const diff = types.Point{
                        .x = pointer.x - points[i].x,
                        .y = pointer.y - points[i].y,
                    };

                    const option_index = if (i == 0 and path.closed) points.len - 1 else if (i > 0) i - 1 else null;
                    if (option_index) |index| {
                        if (!path_utils.isStraightLineHandle(points[index])) {
                            points[index].x += diff.x;
                            points[index].y += diff.y;
                        }
                    }
                    if (i + 1 < points.len - 1) {
                        if (!path_utils.isStraightLineHandle(points[i + 1])) {
                            points[i + 1].x += diff.x;
                            points[i + 1].y += diff.y;
                        }
                    }
                } else {
                    const cp, const option_index = if (i % 3 == 1) blk: {
                        const index = if (i == 1 and path.closed) points.len - 1 else if (i > 1) i - 2 else null;
                        break :blk .{ points[i - 1], index };
                    } else blk: {
                        const index = if (i == points.len - 1 and path.closed) 1 else if (i + 2 < points.len) i + 2 else null;
                        const cp = if (i == points.len - 1 and path.closed) points[0] else points[i + 1];
                        break :blk .{ cp, index };
                    };

                    if (option_index) |index| {
                        const opposite_handler = path_utils.getOppositeHandle(
                            cp,
                            points[i],
                        );

                        const dist = opposite_handler.distance(points[index]);
                        if (dist < 1.0) {
                            points[index] = path_utils.getOppositeHandle(
                                cp,
                                pointer,
                            );
                        }
                    }
                }

                points[i] = pointer;
                shape.outdated_sdf = true;
            }
        }
        return;
    }

    const asset = getSelectedAsset() orelse return;
    const bounds = asset.getBoundsPtr();

    switch (state.action) {
        .Move => {
            state.redraw_needed = true;

            const init_x = state.init_action_bounds[0].x + state.action_pointer_offset.x;
            const init_y = state.init_action_bounds[0].y + state.action_pointer_offset.y;
            const shift_supported_offset = if (constrained) blk: {
                if (@abs(x - init_x) >= @abs(y - init_y)) {
                    break :blk types.Point{ .x = x, .y = init_y };
                } else {
                    break :blk types.Point{ .x = init_x, .y = y };
                }
            } else types.Point{ .x = x, .y = y };

            const first_point = bounds[0];
            for (bounds) |*point| {
                point.x = (point.x - first_point.x) - state.action_pointer_offset.x + shift_supported_offset.x;
                point.y = (point.y - first_point.y) - state.action_pointer_offset.y + shift_supported_offset.y;
            }

            snapshots.triggerNewSnapshot(true, false);
        },
        .Transform => {
            state.redraw_needed = true;

            var safe_copy = state.init_action_bounds;
            transform_ui.transformPoints(
                state.hovered_asset_id.getPrim(),
                &safe_copy,
                types.Point{ .x = x, .y = y },
                constrained,
                maintain_center,
            );
            bounds.* = safe_copy;
            switch (asset.*) {
                .img => {},
                .shape => |*shape| {
                    shape.should_update_sdf = true;
                },
                .text => |*text| {
                    _ = try text.computeText(
                        caret.position,
                        caret.selection_end_position,
                    );

                    const is_text_area_enabled = state.tool == .Text and state.selected_asset_id.isSec();
                    if (is_text_area_enabled) {
                        // This is NOT possible for now
                        // update_text_content(result.content);
                        @panic("Text asset should not be transformable in Text tool");
                    }
                },
            }

            snapshots.triggerNewSnapshot(true, false);
        },
        .TextSelection => {},
        .None => {},
    }
}

pub fn onPointerDoubleClick() !void {
    if (state.tool == .None and getSelectedText() != null) {
        state.redraw_needed = true;
        try setTool(Tool.Text);
        js_glue.onUpdateTool(@intFromEnum(Tool.Text));
    }
}

pub fn onPointerLeave() !void {
    state.redraw_needed = true;
    state.action = .None;
    state.hovered_asset_id = AssetId{};
}

pub fn commitChanges() !void {
    state.redraw_needed = true;

    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            shape.updateControlPointPreview(null);
        }

        shapes.resetState();
    }

    const is_text_area_enabled = state.tool == .Text and state.selected_asset_id.isSec();
    if (is_text_area_enabled) {
        disable_typing();
        caret.position = 0;
        caret.selection_end_position = 0;
    }
}

fn drawBorder(allocator: std.mem.Allocator) !void {
    var triangle_vertex_data = std.ArrayList(triangles.DrawInstance).init(allocator);
    var ui_vertex_data = std.ArrayList(UI.DrawVertex).init(allocator);

    if (state.hovered_asset_id.getPrim() != state.selected_asset_id.getPrim()) {
        if (state.assets.get(state.hovered_asset_id.getPrim())) |asset| {
            try triangle_vertex_data.appendSlice(
                &transform_ui.getBorderDrawVertex(asset, false),
            );
        }
    }

    if (getSelectedAsset()) |asset| {
        try triangle_vertex_data.appendSlice(
            &transform_ui.getBorderDrawVertex(asset.*, true),
        );

        if (state.tool != .Text) {
            const buffers = transform_ui.getDrawVertexData(
                asset.getBounds(),
                state.hovered_asset_id.getPrim(),
            );
            try ui_vertex_data.append(buffers.icon_vertex_data);
            try triangle_vertex_data.appendSlice(&buffers.triangles);
        }
    }

    if (triangle_vertex_data.items.len > 0) {
        web_gpu_programs.draw_triangle(triangle_vertex_data.items);
    }

    try UI.draw(ui_vertex_data.items, web_gpu_programs.draw_shape);
}

fn drawProjectBackground() void {
    var buffer: [2]triangles.DrawInstance = undefined;
    rects.getDrawVertexData(
        &buffer,
        null,
        0.0,
        0.0,
        state.width,
        state.height,
        0.0,
        [_]u8{ 30, 30, 30, 255 },
    );
    web_gpu_programs.draw_triangle(&buffer);
}

fn drawProjectBoundary() void {
    var buffer: [2 * 4]triangles.DrawInstance = undefined;

    const points = [_]types.Point{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = state.width, .y = 0.0 },
        .{ .x = state.width, .y = state.height },
        .{ .x = 0.0, .y = state.height },
    };

    const color = [_]u8{ 127, 127, 127, 255 }; // gray color

    for (points, 0..) |point, i| {
        const next_point = if (i == 3) points[0] else points[i + 1];

        lines.getDrawVertexData(
            buffer[i * 2 ..][0..2],
            point,
            next_point,
            2.0 * shared.ui_scale,
            color,
            0.0,
        );
    }

    web_gpu_programs.draw_triangle(&buffer);
}

fn requestCharsSdfs() !void {
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => {},
            .text => |*text| {
                if (!text.is_sdf_outdated) continue;

                if (!fonts.fonts.contains(text.typo_props.font_family_id)) {
                    continue;
                }

                const padding = sdf_drawing.getSdfPadding(text.effects.items);

                for (text.text_vertex.items) |vertex| {
                    if (vertex.char) |char| {
                        const ch_d = try fonts.get(text.typo_props.font_family_id, char);

                        ch_d.request_size(
                            text.typo_props.font_size,
                            padding,
                        );
                    }
                }
            },
        }
    }
}

pub fn computeSdfs() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try requestCharsSdfs();

    var fonts_iter = fonts.fonts.iterator();
    // outer:
    while (fonts_iter.next()) |font_entry| {
        var font = font_entry.value_ptr.*;
        var char_iter = font.chars.iterator();

        while (char_iter.next()) |char_details_entry| {
            var ch_d = char_details_entry.value_ptr.*;

            if (ch_d.sdf_texture_id) |sdf_texture_id| {
                if (!ch_d.outdated_sdf) continue;
                const font_size = ch_d.max_font_size;
                const ch_w = font_size * ch_d.width;
                const ch_h = font_size * ch_d.height;

                const bounds = utils.createBounds(ch_w, ch_h);
                const padding = font_size * ch_d.*.max_ratio_padding_to_font_size;
                const sdf_dims = sdf_drawing.getSdfTextureDims(
                    bounds,
                    padding,
                    false,
                    1.0,
                );
                ch_d.sdf_scale = sdf_dims.scale;
                // max requested size is not actual generated(like real_viewport_font_size below is)
                // it's max requested size in viewport coords to avoid re-requesting same size again
                const real_viewport_font_size = font_size * ch_d.sdf_scale;

                const viewport_padding = padding * sdf_dims.scale;
                const points = try allocator.dupe(types.Point, ch_d.points);

                for (points) |*point| {
                    if (path_utils.isStraightLineHandle(point.*)) continue;
                    point.x = (point.x * real_viewport_font_size) + viewport_padding;
                    point.y = (point.y * real_viewport_font_size) + viewport_padding;
                }

                web_gpu_programs.compute_shape(
                    points,
                    @intFromFloat(sdf_dims.size.w),
                    @intFromFloat(sdf_dims.size.h),
                    sdf_texture_id,
                );

                ch_d.outdated_sdf = false;
                // break :outer;
            }
        }
    }

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const is_throttle_event = shared.ticks % 5 == 0;
                // in the future we might do throttle depends on the number of selected shapes
                // also instead of ticks we can do (ticks + shape.id) to avoid making all updates at once
                const do_update = shape.outdated_sdf or (shape.should_update_sdf and is_throttle_event);
                if (!do_update) continue;

                const option_points = try shape.getRelativePoints(allocator);
                if (option_points) |points| {
                    const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
                    // TODO: geenrate 20% bigger
                    const sdf_dims = sdf_drawing.getSdfTextureDims(
                        shape.bounds,
                        sdf_padding,
                        false,
                        1.0,
                    );
                    shape.sdf_size = sdf_dims.size;
                    shape.sdf_scale = sdf_dims.scale;

                    for (points) |*point| {
                        point.x += sdf_padding;
                        point.y += sdf_padding;

                        point.x *= shape.sdf_scale;
                        point.y *= shape.sdf_scale;
                    }

                    web_gpu_programs.compute_shape(
                        points,
                        @intFromFloat(shape.sdf_size.w),
                        @intFromFloat(shape.sdf_size.h),
                        shape.sdf_texture_id,
                    );

                    shape.outdated_cache = true;
                }

                shape.outdated_sdf = false;
                shape.should_update_sdf = false;
            },
            .text => |*text| {
                if (text.typo_props.is_sdf_shared) {
                    if (!text.is_sdf_outdated) continue;

                    if (!fonts.fonts.contains(text.typo_props.font_family_id)) {
                        continue;
                    }

                    const text_sdf_texture_id = text.getSdfTextureId();
                    const text_padding = sdf_drawing.getSdfPadding(text.effects.items);
                    const sdf_dims = sdf_drawing.getSdfTextureDims(
                        text.bounds,
                        text_padding,
                        true,
                        1.2,
                    );
                    text.sdf_scale = sdf_dims.scale;

                    const bounds_height = text.bounds[0].distance(text.bounds[3]);

                    const compute_depth_texture_id = js_glue.createDisposableComputeDepthTexture(
                        @intFromFloat(sdf_dims.size.w),
                        @intFromFloat(sdf_dims.size.h),
                    );

                    web_gpu_programs.clear_sdf(
                        text_sdf_texture_id,
                        compute_depth_texture_id,
                        @intFromFloat(sdf_dims.size.w),
                        @intFromFloat(sdf_dims.size.h),
                    );

                    for (text.text_vertex.items) |vertex| {
                        if (vertex.char) |char| {
                            const ch_d = try fonts.get(text.typo_props.font_family_id, char);

                            if (ch_d.sdf_texture_id) |char_sdf_texture_id| {
                                const char_padding = text.typo_props.font_size * ch_d.max_ratio_padding_to_font_size;

                                const start_x = vertex.relative_bounds[3].x - char_padding;
                                const start_y = bounds_height + vertex.relative_bounds[3].y - char_padding;
                                const end_x = vertex.relative_bounds[1].x + char_padding;
                                const end_y = bounds_height + vertex.relative_bounds[1].y + char_padding;

                                const placement = Placement{
                                    .x = (text_padding + start_x) * text.sdf_scale,
                                    .y = (text_padding + start_y) * text.sdf_scale,
                                    .width = (end_x - start_x) * text.sdf_scale,
                                    .height = (end_y - start_y) * text.sdf_scale,
                                };

                                web_gpu_programs.combine_sdf(
                                    text_sdf_texture_id,
                                    char_sdf_texture_id,
                                    compute_depth_texture_id,
                                    placement,
                                );
                            }
                        }
                    }

                    text.is_sdf_outdated = false;
                    text.last_sdf_dim_width = sdf_dims.size.w;
                    text.last_sdf_padding = text_padding;
                }
            },
        }
    }
}

pub fn updateCache() void {
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                if (shape.props.blur) |blur| {
                    if (!shape.outdated_cache) continue;

                    const cache_texture_id: u32 = if (shape.cache_texture_id) |id| id else b: {
                        const id = js_glue.createCacheTexture();
                        shape.cache_texture_id = id;
                        break :b id;
                    };

                    const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
                    const bounds = sdf_drawing.getBoundsWithPadding(
                        shape.bounds,
                        sdf_padding,
                        1 / shared.render_scale,
                        // WARNING: here 1px safety padding changes into 1/shared.render_scale
                        shape.getFilterMargin(),
                    );
                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
                    const size, const sigma, const cache_scale = texture_size.get_safe_blur_dims(
                        init_width,
                        bounds,
                        blur,
                    );

                    if (size.w < consts.MIN_TEXTURE_SIZE or size.h < consts.MIN_TEXTURE_SIZE) continue;
                    // just to make sure device.createTexture won't round number down to 0
                    shape.cache_scale = cache_scale;

                    const bb = bounding_box.BoundingBox{
                        .min_x = 0,
                        .min_y = 0,
                        .max_x = size.w,
                        .max_y = size.h,
                    };
                    js_glue.startCache(cache_texture_id, bb, size.w, size.h);

                    // sigma * 3 -> half of gaussian filter size, does not work in 100% cases but almost
                    const p = types.Point{
                        .x = sigma.x * 3,
                        .y = sigma.y * 3,
                    };
                    const vertex_bounds = [_]types.PointUV{
                        // first triangle
                        .{ .x = p.x, .y = p.y, .u = 0, .v = 0 },
                        .{ .x = p.x, .y = size.h - p.y, .u = 0, .v = 1 },
                        .{ .x = size.w - p.x, .y = size.h - p.y, .u = 1, .v = 1 },
                        // second triangle
                        .{ .x = size.w - p.x, .y = size.h - p.y, .u = 1, .v = 1 },
                        .{ .x = size.w - p.x, .y = p.y, .u = 1, .v = 0 },
                        .{ .x = p.x, .y = p.y, .u = 0, .v = 0 },
                    };

                    for (shape.effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &vertex_bounds,
                            shape.getDrawUniform(effect),
                            shape.sdf_texture_id,
                        );
                    }

                    js_glue.endCache();

                    // Calculate dynamic iterations based on sigma to maintain consistent blur strength
                    const maxSigma = @max(sigma.x, sigma.y);
                    const maxSigmaPerPass = 2.0; // Feel free to increase to 4.0 for betetr quality

                    // Calculate required iterations to achieve target sigma
                    const iterations = @max(1, @ceil(maxSigma / maxSigmaPerPass));

                    // Calculate per-pass sigma values
                    const sigma_per_pass_x = sigma.x / @sqrt(iterations);
                    const sigma_per_pass_y = sigma.y / @sqrt(iterations);

                    // Calculate per-pass filter sizes from per-pass sigma
                    const factor = 1.5 * maxSigmaPerPass;
                    const filter_size_per_pass_x = @ceil(factor * sigma_per_pass_x);
                    const filter_size_per_pass_y = @ceil(factor * sigma_per_pass_y);

                    web_gpu_programs.draw_blur(
                        cache_texture_id,
                        @as(u32, @intFromFloat(iterations)),
                        @as(u32, @intFromFloat(filter_size_per_pass_x)) | 1, // Ensure odd and it's min 1
                        @as(u32, @intFromFloat(filter_size_per_pass_y)) | 1,
                        sigma_per_pass_x,
                        sigma_per_pass_y,
                    );

                    shape.outdated_cache = false;
                }
            },
            .text => {},
        }
    }
}

pub fn setCaretPosition(start: u32, end: u32) void {
    state.redraw_needed = true;

    caret.position = start;
    caret.last_update = shared.time_u32;
    caret.selection_end_position = end;
}

pub fn renderDraw(is_ui_hidden: bool) !void {
    state.redraw_needed = false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    drawProjectBackground();

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: [6]types.PointUV = undefined;
                img.getRenderVertexData(&vertex_data);
                web_gpu_programs.draw_texture(&vertex_data, img.texture_id);
            },
            .shape => |*shape| {
                const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
                if (shape.cache_texture_id) |cache_texture_id| {
                    web_gpu_programs.draw_texture(
                        &sdf_drawing.getDrawBounds(
                            shape.bounds,
                            sdf_padding,
                            shape.getFilterMargin(),
                        ),
                        cache_texture_id,
                    );
                } else {
                    for (shape.effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &sdf_drawing.getDrawBounds(
                                shape.bounds,
                                sdf_padding,
                                shape.getFilterMargin(),
                            ),
                            shape.getDrawUniform(effect),
                            shape.sdf_texture_id,
                        );
                    }
                }
            },
            .text => |*text| {
                if (!fonts.fonts.contains(text.typo_props.font_family_id)) {
                    continue;
                }

                const is_typing_ui = !is_ui_hidden and state.tool == .Text and state.selected_asset_id.getPrim() == text.id;

                if (text.typo_props.is_sdf_shared) {
                    const text_sdf_texture_id = text.getSdfTextureId();

                    const padding = sdf_drawing.getSdfPadding(text.effects.items);
                    for (text.effects.items) |effect| {
                        const text_bounds = sdf_drawing.getDrawBounds(
                            text.bounds,
                            padding,
                            null,
                        );
                        web_gpu_programs.draw_shape(
                            &text_bounds,
                            text.getDrawUniform(effect, text.sdf_scale),
                            text_sdf_texture_id,
                        );
                    }

                    if (!is_typing_ui) continue;
                }

                const selection_start = @min(caret.position, caret.selection_end_position);
                const selection_end = @max(caret.position, caret.selection_end_position);
                var vertex_triangles_buffer =
                    std.ArrayList(triangles.DrawInstance).init(allocator);
                const matrix = Matrix3x3.getMatrixFromRectangleNoScale(text.bounds);

                for (text.text_vertex.items, 0..) |vertex, i| {
                    if (vertex.char) |char| {
                        if (!text.typo_props.is_sdf_shared) {
                            const ch_d = try fonts.get(text.typo_props.font_family_id, char);

                            if (ch_d.sdf_texture_id) |sdf_texture_id| {
                                for (text.effects.items) |effect| {
                                    const bounds = vertex.getBoundsVertex(text.typo_props.font_size * ch_d.max_ratio_padding_to_font_size, matrix);
                                    const char_sdf_viewport_font_size = ch_d.max_font_size * ch_d.sdf_scale;
                                    const sdf_scale = char_sdf_viewport_font_size / text.typo_props.font_size;

                                    web_gpu_programs.draw_shape(
                                        &bounds,
                                        text.getDrawUniform(effect, sdf_scale),
                                        sdf_texture_id,
                                    );
                                }
                            }
                        }

                        if (is_typing_ui) {
                            const is_selection = selection_start != selection_end;

                            if (!is_selection and caret.position == i and caret.isCaretShown()) {
                                const caret_buffer = caret.addDrawVertex(
                                    text,
                                    vertex.relative_bounds[3].toPoint(),
                                );
                                if (caret_buffer) |buffer| {
                                    try vertex_triangles_buffer.appendSlice(&buffer);
                                }
                            }

                            if (is_selection and i >= selection_start and i < selection_end) {
                                try vertex_triangles_buffer.appendSlice(
                                    &text.addTextSelectionDrawVertex(vertex),
                                );
                            }
                        }
                    }
                }

                // if caret is at the end of text
                if (caret.position == text.text_vertex.items.len and caret.isCaretShown()) {
                    const position =
                        if (text.text_vertex.getLastOrNull()) |last_vertex|
                            last_vertex.relative_bounds[2].toPoint()
                        else
                            types.Point{
                                .x = 0,
                                .y = -text.typo_props.font_size * text.typo_props.line_height,
                            };
                    if (caret.addDrawVertex(text, position)) |buffer| {
                        try vertex_triangles_buffer.appendSlice(&buffer);
                    }
                }

                if (is_typing_ui and vertex_triangles_buffer.items.len > 0) {
                    web_gpu_programs.draw_triangle(vertex_triangles_buffer.items);
                }
            },
        }
    }

    if (is_ui_hidden) {
        return;
    }

    drawProjectBoundary(); // TODO: once we support strokes for triangles, we should use it here with transparent fill

    if (state.tool == .None or state.tool == .Text) {
        try drawBorder(allocator);
    }

    if (state.tool == Tool.DrawShape or state.tool == Tool.EditShape) {
        const hover_point_id = state.hovered_asset_id;

        if (getSelectedShape()) |shape| {
            const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
            web_gpu_programs.draw_shape(
                &sdf_drawing.getDrawBounds(
                    shape.bounds,
                    sdf_padding,
                    null,
                ),
                shape.getSkeletonUniform(),
                shape.sdf_texture_id,
            );

            const hover_id = if (shape.id == hover_point_id.getPrim()) hover_point_id else null;
            const vertex_data = try shape.getSkeletonDrawVertexData(
                allocator,
                hover_id,
                state.tool == Tool.DrawShape,
            );
            web_gpu_programs.draw_triangle(vertex_data);
        }
    }
}

pub fn renderPick() !void {
    if (state.tool == Tool.DrawShape) {
        return;
    }

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: [6]images.PickVertex = undefined;
                img.getPickVertexData(&vertex_data);

                web_gpu_programs.pick_texture(&vertex_data, img.texture_id);
            },
            .shape => |shape| {
                for (shape.effects.items) |effect| {
                    web_gpu_programs.pick_shape(
                        &shape.getPickBounds(),
                        shape.getPickUniform(effect),
                        shape.sdf_texture_id,
                    );
                }
            },
            .text => |text| {
                if (state.action == .TextSelection) continue; // while selecting text I need only active/selected text asset

                // if there is any text selected, render pick for only that text(at the end to make sure selected text is a priority)
                if (state.tool == Tool.Text and state.selected_asset_id.getPrim() == text.id) continue;

                const buffer = try text.addPickVertex(
                    std.heap.page_allocator,
                    0,
                );
                web_gpu_programs.pick_triangle(buffer);
                std.heap.page_allocator.free(buffer);
            },
        }
    }

    if (state.tool == Tool.Text) {
        if (getSelectedText()) |text| {
            const overflow_margin_factor = if (state.action == .TextSelection) 300 * shared.ui_scale else 0;
            const buffer = try text.addPickVertex(
                std.heap.page_allocator,
                overflow_margin_factor,
            );
            web_gpu_programs.pick_triangle(buffer);
            std.heap.page_allocator.free(buffer);
        }
    }

    if (state.tool == Tool.EditShape) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        if (getSelectedShape()) |shape| {
            const vertex_data = try shape.getSkeletonPickVertexData(allocator);
            web_gpu_programs.pick_triangle(vertex_data);
        }
    }

    if (state.tool == Tool.None) {
        if (getSelectedAsset()) |asset| {
            const bounds = asset.getBounds();
            var vertex_buffer: [transform_ui.PICK_TRIANGLE_INSTANCES]triangles.PickInstance = undefined;
            transform_ui.getPickVertexData(vertex_buffer[0..transform_ui.PICK_TRIANGLE_INSTANCES], bounds);
            web_gpu_programs.pick_triangle(vertex_buffer[0..transform_ui.PICK_TRIANGLE_INSTANCES]);
        }
    }
}

pub fn setSnapshot(snapshot: snapshots.ProjectSnapshot, with_snapshot: bool) !void {
    state.redraw_needed = true;
    state.width = snapshot.width;
    state.height = snapshot.height;

    snapshots.skip_snapshot = true;
    shapes.resetState();
    state.assets.clearAndFree();

    for (snapshot.assets) |asset| {
        switch (asset) {
            .img => |img| {
                try addImage(img.id, img.bounds, img.texture_id);
            },
            .shape => |shape| {
                _ = try addShape(
                    shape.id,
                    shape.paths,
                    shape.bounds,
                    shape.props,
                    shape.effects,
                    shape.sdf_texture_id,
                    shape.cache_texture_id,
                );
            },
            .text => |text| {
                _ = try addText(
                    text.id,
                    text.content orelse "", // should always be provided in real-life executions
                    text.bounds,
                    text.props,
                    text.effects,
                    text.typo_props,
                    text.sdf_texture_id,
                );
            },
        }
    }

    // deselect asset if it's removed (was not present in the snapshot)
    if (!state.assets.contains(state.selected_asset_id.getPrim())) {
        try setSelectedAsset(AssetId{});
    }
    snapshots.skip_snapshot = false;
    snapshots.triggerNewSnapshot(with_snapshot, true);
}

pub fn deinitState() void {
    var it = state.assets.iterator();
    while (it.next()) |entry| {
        switch (entry.value_ptr.*) {
            .img => {},
            .shape => |*shape| shape.deinit(),
            .text => |*text| text.deinit(),
        }
    }
    state.assets.clearAndFree();
    UI.deinit();
    snapshots.deinit();
    state.selected_asset_id = AssetId{};
    state.hovered_asset_id = AssetId{};
    next_asset_id = ASSET_ID_MIN;
    web_gpu_programs = undefined;
    // state itself is not destoyed as it will be reinitalized before usage
    // and has no reference to memory to free
}

pub fn importUiElement(
    id: u32,
    paths: []const []const types.Point,
    sdf_texture_id: u32,
) !void {
    try UI.importUiElement(id, paths, sdf_texture_id);
}

pub fn generateUiElementsSdf() !void {
    try UI.generateUiElementsSdf(web_gpu_programs.compute_shape);
}

pub fn setTool(tool: Tool) !void {
    try commitChanges();
    state.tool = tool;

    if (tool == .Text) {
        if (getSelectedText()) |text| {
            enable_typing(text.content);
        }
    }
}

// returns bool indicating if an update in drawing is needed
var lastIsCaretShown = false;
pub fn tick(now: f32) !bool {
    shared.tick(now);
    try snapshots.loop(state);

    if (!state.redraw_needed and state.tool == .Text and getSelectedText() != null) {
        const isCaretShown = caret.isCaretShown();

        if (isCaretShown != lastIsCaretShown) {
            lastIsCaretShown = isCaretShown;
            return true;
        }
    }

    return state.redraw_needed;
}

pub fn setSelectedAssetTypoProps(serialized: typography_props.Serialized, commit: bool) !void {
    if (getSelectedText()) |text| {
        const new_typo_props = typography_props.deserialize(serialized);
        text.typo_props = new_typo_props;

        const result = try text.computeText(0, 0);

        const is_text_area_enabled = state.tool == .Text and state.selected_asset_id.isSec();

        if (is_text_area_enabled) {
            // although this should not really happen, if user changes font properties,
            // then it's not longer in typing tool in the textbox
            update_text_content(result.content);
            // new soft breaks might appear after font change
        }

        if (text.typo_props.is_sdf_shared) {
            text.is_sdf_outdated = true;
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn setSelectedAssetEffects(serialized_effects: []const sdf_effect.Serialized, commit: bool) !void {
    if (getSelectedAsset()) |asset| {
        switch (asset.*) {
            .img => {},
            .shape => |*shape| {
                sdf_effect.deinit(shape.effects);
                shape.effects = try sdf_effect.deserialize(serialized_effects, std.heap.page_allocator);
                shape.outdated_sdf = true;
            },
            .text => |*text| {
                sdf_effect.deinit(text.effects);
                text.effects = try sdf_effect.deserialize(serialized_effects, std.heap.page_allocator);
                if (text.typo_props.is_sdf_shared) {
                    const new_padding = sdf_drawing.getSdfPadding(text.effects.items);
                    if (new_padding > text.last_sdf_padding) {
                        text.is_sdf_outdated = true;
                    }
                }
            },
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn setSelectedAssetProps(props: asset_props.Props, commit: bool) !void {
    if (getSelectedAsset()) |asset| {
        switch (asset.*) {
            .img => {},
            .shape => |*shape| {
                shape.props = props;
                if (props.blur == null and shape.cache_texture_id != null) {
                    // TODO: https://github.com/mateuszJS/magic-render/issues/204
                    // destroy_texture(shape.cache_texture_id);

                    shape.cache_texture_id = null;
                } else if (props.blur != null and shape.cache_texture_id == null) {
                    shape.cache_texture_id = js_glue.createCacheTexture();
                }
                shape.outdated_cache = true; // we could also check if blur exists even
            },
            .text => |*text| {
                text.props = props;
            },
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn setSelectedAssetBounds(bounds: [4]types.PointUV, commit: bool) !void {
    // pub fn setSelectedAssetBounds(
    //     offset_x: f32,
    //     offset_y: f32,
    //     origin: u32, // 0 -> Move, 1-9 -> transform ui handles
    // ) !void {
    // const asset = getSelectedAsset() orelse return;
    // const bounds = asset.getBoundsPtr();

    // const handle = switch (origin) {
    //     1 => bounds[0].toPoint(),
    //     2 => bounds[1].toPoint(),
    //     3 => bounds[2].toPoint(),
    //     4 => bounds[3].toPoint(),
    //     5 => bounds[0].mid(bounds[1]),
    //     6 => bounds[1].mid(bounds[2]),
    //     7 => bounds[2].mid(bounds[3]),
    //     8 => bounds[3].mid(bounds[0]),
    //     else => @panic("Invalid origin"),
    // };

    // switch (state.action) {
    //     .Move => {
    //         for (bounds) |*point| {
    //             point.x += offset_x;
    //             point.y += offset_y;
    //         }

    //         asset_observer.triggerUpdate();
    //     },
    //     .Transform => {
    //         transform_ui.transformPoints(
    //             origin,
    //             bounds,
    //             types.Point{ .x = offset_x, .y = offset_y },
    //         );
    //         switch (asset.*) {
    //             .img => {},
    //             .shape => |*shape| {
    //                 shape.should_update_sdf = true;
    //             },
    //             .text => |*text| {
    //                 const result = try text.computeText(
    //                     texts.caret_position,
    //                     texts.selection_end_position,
    //                 );

    //                 if (state.tool == .Text) {
    //                     update_text_content(result.content);
    //                 }
    //             },
    //         }

    //         asset_observer.triggerUpdate();
    //     },
    //     .TextSelection => {},
    //     .None => {},
    // }

    // TODO: code duplication with transform_ui

    if (getSelectedAsset()) |asset| {
        switch (asset.*) {
            .img => |*img| {
                img.bounds = bounds;
            },
            .shape => |*shape| {
                shape.bounds = bounds;
                // shape.should_update_sdf = true; on 99% is not needed
            },
            .text => |*text| {
                text.bounds = bounds;
                const result = try text.computeText(
                    caret.position,
                    caret.selection_end_position,
                );

                const is_text_area_enabled = state.tool == .Text and state.selected_asset_id.isSec();
                if (is_text_area_enabled) {
                    update_text_content(result.content);
                }
            },
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn addFont(font_id: u32) !void {
    try fonts.new(font_id);

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => {},
            .text => |*text| {
                if (text.typo_props.font_family_id == font_id) {
                    state.redraw_needed = true;

                    const result = try text.computeText(0, 0);
                    const is_text_area_enabled = state.tool == .Text and state.selected_asset_id.isSec();
                    if (is_text_area_enabled and text.id == state.selected_asset_id.getPrim()) {
                        // new soft breaks might appear after font change
                        update_text_content(result.content);
                    }
                }
            },
        }
    }
}

pub fn onBlurTextArea() void {
    if (state.tool == .Text) {
        state.redraw_needed = true;

        // leave typing mode, focus is not longer in text area
        state.selected_asset_id = AssetId.fromArray(.{ state.selected_asset_id.getPrim(), 0, 0, 0 });
        caret.position = 0;
        caret.selection_end_position = 0;
    }
}

// Invalidates cache for given asset ids
// Useful when a resource is ready to be rendered, e.g. image, font, program finished compiling
// but that resource loading did not trigger a change in asset serialized state
// so you have to explicitly invalidate cache to re-render with newest resource version
pub fn invalidateCache(ids: []const u32) void {
    for (ids) |id| {
        if (state.assets.getPtr(id)) |asset| {
            switch (asset.*) {
                .img => {},
                .shape => |*shape| {
                    state.redraw_needed = true;
                    shape.outdated_cache = true;
                },
                .text => {},
            }
        }
    }
}
