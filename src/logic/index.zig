const std = @import("std");
const types = @import("types.zig");
const images = @import("images.zig");
const lines = @import("lines.zig");
const triangles = @import("triangles.zig");
const TransformUI = @import("transform_ui.zig");
const zigar = @import("zigar");
const shapes = @import("./shapes/shapes.zig");
const rects = @import("rects.zig");
const bounding_box = @import("shapes/bounding_box.zig");
const shared = @import("shared.zig");
const texture_size = @import("texture_size.zig");
const Utils = @import("utils.zig");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const PathUtils = @import("shapes/path_utils.zig");
const consts = @import("consts.zig");
const UI = @import("ui.zig");
const texts = @import("texts/texts.zig");
const sdf = @import("sdf/sdf.zig");
const fonts = @import("texts/fonts.zig");
const AssetId = @import("asset_id.zig").AssetId;

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
    draw_shape: *const fn ([]const types.PointUV, sdf.DrawUniform, u32) void,
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

var on_asset_update_cb: ?*const fn ([]const AssetSerialized) void = undefined;
var original_on_asset_update_cb: ?*const fn ([]const AssetSerialized) void = undefined;

pub fn connectOnAssetUpdateCallback(cb: *const fn ([]const AssetSerialized) void) void {
    on_asset_update_cb = cb;
    original_on_asset_update_cb = cb;
}

var on_asset_select_cb: *const fn ([4]u32) void = undefined;
pub fn connectOnAssetSelectionCallback(cb: *const fn ([4]u32) void) void {
    on_asset_select_cb = cb;
}

var create_sdf_texture: *const fn () u32 = undefined;
var create_compute_depth_texture: *const fn (u32, u32) u32 = undefined;
pub fn connectCreateSdfTexture(
    create_sdf: *const fn () u32,
    create_compute_depth: *const fn (u32, u32) u32,
) void {
    create_sdf_texture = create_sdf;
    create_compute_depth_texture = create_compute_depth;
}

pub const SerializedCharDetails = fonts.SerializedCharDetails;

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
    get_char_data: *const fn (u32, u21) fonts.SerializedCharDetails,
    get_kerning: *const fn (u21, u21) f32,
) void {
    enable_typing = enable;
    disable_typing = disable;
    update_text_content = update_content;
    update_text_selection = update_selection;
    fonts.getCharData = get_char_data;
    fonts.getKerning = get_kerning;
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

var create_cache_texture: *const fn () u32 = undefined;
var start_cache: *const fn (u32, bounding_box.BoundingBox, f32, f32) void = undefined;
var end_cache: *const fn () void = undefined;

pub fn connectCacheCallbacks(
    create_cache_texture_cb: *const fn () u32,
    start_cache_cb: *const fn (u32, bounding_box.BoundingBox, f32, f32) void,
    end_cache_cb: *const fn () void,
) void {
    create_cache_texture = create_cache_texture_cb;
    start_cache = start_cache_cb;
    end_cache = end_cache_cb;
}

pub const ASSET_ID_MIN: u32 = 1000;
const MIN_NEW_CONTROL_POINT_DISTANCE = 10.0; // Minimum distance to consider a new control point

const ActionType = enum {
    Move,
    None,
    Transform,
    TextSelection,
};

const Tool = enum {
    None,
    DrawShape,
    EditShape,
    Text,
};

const Asset = union(enum) {
    img: images.Image,
    shape: shapes.Shape,
    text: texts.Text,
};

const AssetSerialized = union(enum) {
    img: images.Serialized,
    shape: shapes.Serialized,
    text: texts.Serialized,
};

const State = struct {
    width: f32,
    height: f32,
    assets: std.AutoArrayHashMap(u32, Asset),
    hovered_asset_id: AssetId,
    selected_asset_id: AssetId,
    action: ActionType,
    tool: Tool,
    last_pointer_coords: types.Point,
};

var state = State{
    .width = 0,
    .height = 0,
    .assets = undefined,
    .hovered_asset_id = AssetId{},
    .selected_asset_id = AssetId{},
    .action = ActionType.None,
    .tool = Tool.None,
    .last_pointer_coords = types.Point{ .x = 0.0, .y = 0.0 },
};

pub fn initState(width: f32, height: f32, texture_max_size: f32, max_buffer_size: f32) !void {
    shared.texture_max_size = texture_max_size;
    shared.max_buffer_size = max_buffer_size;
    state.width = width;
    state.height = height;
    state.assets = std.AutoArrayHashMap(u32, Asset).init(std.heap.page_allocator);
    UI.init();
    fonts.init();
    try fonts.new(0);
}

pub fn updateRenderScale(scale: f32) !void {
    shared.render_scale = scale;

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
                const new_sdf_dims = sdf.getSdfTextureDims(
                    shape.bounds,
                    sdf_padding,
                );

                if (new_sdf_dims.size.w > shape.sdf_size.w or new_sdf_dims.size.h > shape.sdf_size.h) {
                    shape.outdated_sdf = true;
                }
            },
            .text => |*text| {
                text.is_sdf_outdated = true;
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

pub fn addImage(id_or_zero: u32, points: [4]types.PointUV, texture_id: u32) !void {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const asset = Asset{
        .img = images.Image.new(id, points, texture_id),
    };
    try state.assets.put(id, asset);

    try checkAssetsUpdate(true);
}

pub fn addShape(
    id_or_zero: u32,
    paths: []const []const types.Point,
    bounds: ?[4]types.PointUV,
    props: shapes.SerializedProps,
    sdf_texture_id: u32,
    cache_texture_id: ?u32,
) !u32 {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const shape = try shapes.Shape.new(
        id,
        paths,
        bounds,
        props,
        sdf_texture_id,
        cache_texture_id,
        std.heap.page_allocator,
    );
    try state.assets.put(id, Asset{ .shape = shape });

    try checkAssetsUpdate(true);
    return id;
}

fn addText(
    id_or_zero: u32,
    content: []const u8,
    bounds: [4]types.PointUV,
    font_size: f32,
    props: shapes.SerializedProps,
) !texts.Text {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const text = try texts.Text.new(
        std.heap.page_allocator,
        id,
        content,
        bounds,
        font_size,
        props,
        null,
    );
    try state.assets.put(id, Asset{ .text = text });
    try checkAssetsUpdate(true);
    return text;
}

pub fn removeAsset() !void {
    _ = state.assets.orderedRemove(state.selected_asset_id.getPrim());
    try updateSelectedAsset(AssetId{});
    try checkAssetsUpdate(true);
}

pub fn onUpdatePick(id: [4]u32) void {
    if (state.action != .Transform) {
        state.hovered_asset_id = AssetId.fromArray(id);
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

pub fn addShapeBegin() void {
    on_asset_update_cb = null;
}

pub fn addShapeFinish() !void {
    on_asset_update_cb = original_on_asset_update_cb;
    try checkAssetsUpdate(true);
}

var last_assets_update: []const AssetSerialized = &.{};
fn checkAssetsUpdate(should_notify: bool) !void {
    const cb = on_asset_update_cb orelse return;

    var new_assets_update = std.ArrayList(AssetSerialized).init(std.heap.page_allocator);
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset_entry| {
        switch (asset_entry.value_ptr.*) {
            .img => |img| {
                try new_assets_update.append(AssetSerialized{
                    .img = img.serialize(),
                });
            },
            .shape => |shape| {
                try new_assets_update.append(AssetSerialized{
                    .shape = try shape.serialize(std.heap.page_allocator),
                });
            },
            .text => |text| {
                try new_assets_update.append(AssetSerialized{
                    .text = try text.serialize(std.heap.page_allocator),
                });
            },
        }
    }

    if (new_assets_update.items.len == last_assets_update.len) {
        var all_match = true;
        for (new_assets_update.items, last_assets_update) |new_asset, old_asset| {
            switch (old_asset) {
                .img => |old_img| {
                    if (!std.meta.eql(new_asset.img, old_img)) {
                        all_match = false;
                        break;
                    }
                },
                .shape => |old_shape| {
                    if (!old_shape.compare(new_asset.shape)) {
                        all_match = false;
                        break;
                    }
                },
                .text => |old_text| {
                    if (!std.meta.eql(new_asset.text, old_text)) {
                        all_match = false;
                        break;
                    }
                },
            }
        }

        if (all_match) {
            new_assets_update.clearAndFree();
            new_assets_update.deinit();
            return;
        }
    }

    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = try new_assets_update.toOwnedSlice();

    if (should_notify) {
        if (last_assets_update.len > 0) {
            cb(last_assets_update); // would throw error if results.len == 0
        } else {
            cb(&.{});
        }
    }
}

fn getSelectedImg() ?*images.Image {
    const asset = state.assets.getPtr(state.selected_asset_id.getPrim()) orelse return null;
    switch (asset.*) {
        .img => |*img| return img,
        .shape => return null,
        .text => return null,
    }
}

fn getSelectedShape() ?*shapes.Shape {
    const asset = state.assets.getPtr(state.selected_asset_id.getPrim()) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
        .text => return null,
    }
}

fn getSelectedText() ?*texts.Text {
    const asset = state.assets.getPtr(state.selected_asset_id.getPrim()) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => return null,
        .text => |*text| return text,
    }
}

fn updateSelectedAsset(id: AssetId) !void {
    try commitChanges();
    state.selected_asset_id = id;
    on_asset_select_cb(id.serialize());
}

pub fn updateTextContent(
    content: []const u8,
    selection_start: usize,
    selection_end: usize,
) !texts.ComputeTextResult {
    const option_text = getSelectedText();
    if (option_text) |text| {
        text.content = content;
        return try text.computeText(selection_start, selection_end);
    } else {
        @panic("updateTextContent called but no text asset selected");
    }
}

pub fn onPointerDown(x: f32, y: f32) !void {
    if (state.tool == .Text) {
        try updateSelectedAsset(state.hovered_asset_id);

        const text: texts.Text = if (getSelectedText()) |text| b: {
            break :b text.*;
        } else b: {
            const id = generateId();
            const max_width = 300.0;
            const bounds = [4]types.PointUV{
                .{ .x = x, .y = y, .u = 0.0, .v = 1.0 },
                .{ .x = x + max_width, .y = y, .u = 1.0, .v = 1.0 },
                .{ .x = x + max_width, .y = y - 1.0, .u = 1.0, .v = 0.0 },
                .{ .x = x, .y = y - 1.0, .u = 0.0, .v = 0.0 },
            };

            const props = shapes.SerializedProps{
                .sdf_effects = &.{
                    shapes.SerializedSdfEffect{
                        .dist_start = std.math.inf(f32),
                        .dist_end = 0,
                        .fill = .{ .solid = .{ 1.0, 0.0, 1.0, 1.0 } },
                    },
                    // shapes.SerializedSdfEffect{
                    //     .dist_start = 3,
                    //     .dist_end = 1.5,
                    //     .fill = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
                    // },
                    // shapes.SerializedSdfEffect{
                    //     .dist_start = -6,
                    //     .dist_end = -8,
                    //     .fill = .{ .solid = .{ 1.0, 0.0, 0.0, 1.0 } },
                    // },
                },
                .filter = null,
                .opacity = 1.0,
            };

            const new_text = try addText(
                id,
                "A",
                // "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
                bounds,
                72.0,
                props,
            );
            try updateSelectedAsset(AssetId{ ._prim = id });
            break :b new_text;
        };

        enable_typing(text.serialized_updated_content);

        if (state.hovered_asset_id.isSec()) {
            state.selected_asset_id.setSec(state.hovered_asset_id.getSec());

            const caret_index = state.hovered_asset_id.getSec();
            setCaretPosition(caret_index, caret_index);
            update_text_selection(caret_index, caret_index);
        }

        state.action = .TextSelection;
    } else if (state.tool == Tool.DrawShape) {
        if (getSelectedShape() == null) {
            const props = shapes.SerializedProps{
                .sdf_effects = &.{
                    shapes.SerializedSdfEffect{
                        .dist_start = std.math.inf(f32),
                        .dist_end = 0,
                        .fill = .{ .solid = .{ 1.0, 0.0, 1.0, 1.0 } },
                    },
                    shapes.SerializedSdfEffect{
                        .dist_start = 26,
                        .dist_end = 24,
                        .fill = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
                    },
                    shapes.SerializedSdfEffect{
                        .dist_start = -30,
                        .dist_end = -32,
                        .fill = .{ .solid = .{ 1.0, 0.0, 0.0, 1.0 } },
                    },
                },
                .filter = .{ .gaussianBlur = .{ .x = 30, .y = 30 } },
                .opacity = 1.0,
            };
            const id = try addShape(
                0,
                &.{},
                null,
                props,
                create_sdf_texture(),
                if (props.filter != null) create_cache_texture() else null,
            );
            try updateSelectedAsset(AssetId{ ._prim = id });
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
                try updateSelectedAsset(state.hovered_asset_id);
            }
        }

        if (!state.selected_asset_id.isPrim()) {
            // No active asset, do nothing
        } else if (TransformUI.isTransformUi(state.hovered_asset_id.getPrim())) {
            state.action = .Transform;
        } else if (state.selected_asset_id.getPrim() >= ASSET_ID_MIN and state.selected_asset_id.getPrim() == state.hovered_asset_id.getPrim()) {
            state.action = .Move;
            state.last_pointer_coords = types.Point{ .x = x, .y = y };
        }
    }
}

pub fn onPointerUp() !void {
    if (state.tool == .None) {
        if (state.action == .None) {
            try updateSelectedAsset(state.hovered_asset_id);
        } else {
            state.action = .None;
            try checkAssetsUpdate(true);
        }
    } else if (state.tool == Tool.DrawShape) {
        try checkAssetsUpdate(true);
        if (getSelectedShape()) |shape| {
            shape.onReleasePointer();
        }
    } else if (state.tool == Tool.EditShape) {
        // to remove sec, third, quat fields
        state.selected_asset_id = AssetId{ ._prim = state.selected_asset_id.getPrim() };
    } else if (state.tool == Tool.Text) {
        state.action = .None;
    }
}

pub fn onPointerMove(x: f32, y: f32) !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            shape.updatePointPreview(types.Point{ .x = x, .y = y });
        }
        return;
    }

    if (state.tool == Tool.Text and state.action == .TextSelection) {
        if (getSelectedText() != null) {
            if (state.hovered_asset_id.getPrim() == state.selected_asset_id.getPrim()) {
                if (state.hovered_asset_id.isSec() and state.selected_asset_id.isSec()) {
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
                        if (!PathUtils.isStraightLineHandle(points[index])) {
                            points[index].x += diff.x;
                            points[index].y += diff.y;
                        }
                    }
                    if (i + 1 < points.len - 1) {
                        if (!PathUtils.isStraightLineHandle(points[i + 1])) {
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
                        const opposite_handler = PathUtils.getOppositeHandle(
                            cp,
                            points[i],
                        );

                        const dist = opposite_handler.distance(points[index]);
                        if (dist < 1.0) {
                            points[index] = PathUtils.getOppositeHandle(
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

    const asset = state.assets.getPtr(state.selected_asset_id.getPrim()) orelse return;
    const bounds = switch (asset.*) {
        .img => |*img| &img.points,
        .shape => |*shape| &shape.bounds,
        .text => |*text| &text.bounds,
    };

    switch (state.action) {
        .Move => {
            const offset = types.Point{
                .x = x - state.last_pointer_coords.x,
                .y = y - state.last_pointer_coords.y,
            };
            state.last_pointer_coords = types.Point{ .x = x, .y = y };

            for (bounds) |*point| {
                point.x += offset.x;
                point.y += offset.y;
            }
        },
        .Transform => {
            TransformUI.transformPoints(
                state.hovered_asset_id.getPrim(),
                bounds,
                types.Point{ .x = x, .y = y },
            );
            switch (asset.*) {
                .img => {},
                .shape => |*shape| {
                    shape.should_update_sdf = true;
                },
                .text => |*text| {
                    const result = try text.computeText(
                        texts.caret_position,
                        texts.selection_end_position,
                    );

                    if (state.tool == .Text) {
                        update_text_content(result.content);
                        update_text_selection(result.selection_start, result.selection_end);
                    }
                },
            }
        },
        .TextSelection => {},
        .None => {},
    }
}

pub fn onPointerLeave() !void {
    state.action = .None;
    state.hovered_asset_id = AssetId{};
    try checkAssetsUpdate(true);
}

pub fn commitChanges() !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            shape.update_preview_point(null);
        }

        shapes.resetState();
    }

    if (state.tool == Tool.Text) {
        disable_typing();
        texts.caret_position = 0;
        texts.selection_end_position = 0;
    }
}
// TODO: extract to another file and simplify(extract common code)
// https://github.com/users/mateuszJS/projects/1/views/1?pane=issue&itemId=123400787&issue=mateuszJS%7Cmagic-render%7C122
fn drawBorder(allocator: std.mem.Allocator) !void {
    var triangle_vertex_data = std.ArrayList(triangles.DrawInstance).init(allocator);
    var ui_vertex_data = std.ArrayList(UI.DrawVertex).init(allocator);

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id.getPrim() != state.selected_asset_id.getPrim()) {
        if (state.assets.get(state.hovered_asset_id.getPrim())) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
                .text => |text| text.bounds,
            };

            for (points, 0..) |point, i| {
                const next_point = if (i == 3) points[0] else points[i + 1];
                var buffer: [2]triangles.DrawInstance = undefined;

                lines.getDrawVertexData(
                    buffer[0..2],
                    point,
                    next_point,
                    10.0 * shared.render_scale,
                    red,
                    5.0 * shared.render_scale,
                );

                try triangle_vertex_data.appendSlice(&buffer);
            }
        }
    }

    const green = [_]u8{ 0, 255, 0, 255 };
    if (state.assets.get(state.selected_asset_id.getPrim())) |asset| {
        const points = switch (asset) {
            .img => |img| img.points,
            .shape => |shape| shape.bounds,
            .text => |text| text.bounds,
        };

        for (points, 0..) |point, i| {
            const next_point = if (i == 3) points[0] else points[i + 1];
            var buffer: [2]triangles.DrawInstance = undefined;

            lines.getDrawVertexData(
                buffer[0..2],
                point,
                next_point,
                10.0 * shared.render_scale,
                green,
                5.0 * shared.render_scale,
            );

            try triangle_vertex_data.appendSlice(&buffer);
        }

        var triangle_buffer: [TransformUI.RENDER_TRIANGLE_INSTANCES]triangles.DrawInstance = undefined;

        try TransformUI.getDrawVertexData(
            &triangle_buffer,
            &ui_vertex_data,
            points,
            state.hovered_asset_id.getPrim(),
        );

        try triangle_vertex_data.appendSlice(&triangle_buffer);
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
            2.0 * shared.render_scale,
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

                const padding = sdf.getSdfPadding(text.props.sdf_effects.items);
                // std.debug.print("pppppadddding: {d}-------------\n", .{padding});
                for (text.text_vertex.items) |vertex| {
                    if (vertex.char) |char| {
                        const ch_d = try fonts.get(0, char);

                        ch_d.request_size(
                            text.font_size,
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
    while (fonts_iter.next()) |font_entry| {
        var font = font_entry.value_ptr.*;
        var char_iter = font.chars.iterator();
        while (char_iter.next()) |details_entry| {
            var ch_d = details_entry.value_ptr;
            if (ch_d.sdf_texture_id) |sdf_texture_id| {
                if (!ch_d.outdated_sdf) continue;

                const ch_w = ch_d.max_font_size * ch_d.width;
                const ch_h = ch_d.max_font_size * ch_d.height;

                const bounds = [4]types.PointUV{
                    .{ .x = 0, .y = ch_h, .u = 0, .v = 1 },
                    .{ .x = ch_w, .y = ch_h, .u = 1, .v = 1 },
                    .{ .x = ch_w, .y = 0, .u = 1, .v = 0 },
                    .{ .x = 0, .y = 0, .u = 0, .v = 0 },
                };
                const padding = ch_d.max_font_size * ch_d.max_ratio_padding_to_font_size;
                const sdf_dims = sdf.getSdfTextureDims(bounds, padding);

                ch_d.sdf_scale = sdf_dims.scale;

                // this is NOT viewport, it's SDF scale, if it's smaller htan requested viewport(often while using zoom)
                // we will keep regenerating it for no reason!
                ch_d.max_requested_viewport_font_size = ch_d.max_font_size * sdf_dims.scale;
                const viewport_padding = padding * sdf_dims.scale;
                // ch_d.max_requested_viewport_effect_padding = ch_d.max_effect_padding * ch_d.sdf_scale;

                const points = try std.heap.page_allocator.dupe(types.Point, ch_d.points);
                // std.debug.print("char texture size {d}x{d}\n", .{ sdf_dims.size.w, sdf_dims.size.h });
                // std.debug.print("ch_d.max_effect_padding {d}\n", .{ch_d.max_effect_padding});
                for (points) |*point| {
                    if (PathUtils.isStraightLineHandle(point.*)) {
                        continue;
                    }
                    point.x = (point.x * ch_d.max_requested_viewport_font_size) + viewport_padding;
                    point.y = (point.y * ch_d.max_requested_viewport_font_size) + viewport_padding;
                    // std.debug.print("point: {d}, {d}\n", .{ point.x, point.y });
                }

                web_gpu_programs.compute_shape(
                    points,
                    @intFromFloat(sdf_dims.size.w),
                    @intFromFloat(sdf_dims.size.h),
                    sdf_texture_id,
                );

                ch_d.outdated_sdf = false;
            }
        }
    }

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const is_throttle_event = ticks % 5 == 0;
                // in the future we might do throttle depends on the number of selected shapes
                // also instead of ticks we can do (ticks + shape.id) to avoid making all updates at once
                const do_update = shape.outdated_sdf or (shape.should_update_sdf and is_throttle_event);
                if (!do_update) continue;

                const option_points = try shape.getRelativePoints(allocator);
                if (option_points) |points| {
                    const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
                    const sdf_dims = sdf.getSdfTextureDims(
                        shape.bounds,
                        sdf_padding,
                    );
                    shape.sdf_size = sdf_dims.size;
                    shape.sdf_scale = sdf_dims.scale;

                    for (points) |*point| {
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
                if (!text.is_sdf_outdated) continue;

                const text_padding = sdf.getSdfPadding(text.props.sdf_effects.items);
                const sdf_dims = sdf.getSdfTextureDims(
                    text.bounds,
                    text_padding,
                );
                text.sdf_scale = sdf_dims.scale;

                if (text.sdf_texture_id) |text_sdf_texture_id| {
                    const safe_margin_bottom = 0; //text.font_size * text.line_height; // some ltters like "g" got tail wich excees bottom part outside of bounds
                    _ = safe_margin_bottom; // autofix
                    // we have to include this part in final SDF
                    const text_viewport_height = text.bounds[0].distance(text.bounds[3]);

                    const compute_depth_texture_id = create_compute_depth_texture(
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
                            const ch_d = try fonts.get(0, char);

                            if (ch_d.sdf_texture_id) |char_sdf_texture_id| {
                                const char_padding = text.font_size * ch_d.max_ratio_padding_to_font_size;

                                const start_x = vertex.relative_bounds[3].x - char_padding;
                                const start_y = text_viewport_height + vertex.relative_bounds[3].y - char_padding;
                                const end_x = vertex.relative_bounds[1].x + char_padding;
                                const end_y = text_viewport_height + vertex.relative_bounds[1].y + char_padding;

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
                if (shape.props.filter) |filter| {
                    if (!shape.outdated_cache) continue;

                    const cache_texture_id: u32 = if (shape.cache_texture_id) |id| id else b: {
                        const id = create_cache_texture();
                        shape.cache_texture_id = id;
                        break :b id;
                    };

                    const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
                    const bounds = sdf.getBoundsWithPadding(
                        shape.bounds,
                        sdf_padding,
                        1 / shared.render_scale,
                        shape.getFilterMargin(),
                    );
                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
                    const size, const sigma, const cache_scale = texture_size.get_safe_blur_dims(
                        init_width,
                        bounds,
                        filter.gaussianBlur,
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
                    start_cache(cache_texture_id, bb, size.w, size.h);

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

                    for (shape.props.sdf_effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &vertex_bounds,
                            shape.getDrawUniform(effect),
                            shape.sdf_texture_id,
                        );
                    }

                    end_cache();

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
    texts.caret_position = start;
    texts.last_caret_update = shared.time_u32;
    texts.selection_end_position = end;
}

pub fn renderDraw() !void {
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
                const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
                if (shape.cache_texture_id) |cache_texture_id| {
                    web_gpu_programs.draw_texture(
                        &sdf.getDrawBounds(
                            shape.bounds,
                            sdf_padding,
                            shape.getFilterMargin(),
                        ),
                        cache_texture_id,
                    );
                } else {
                    for (shape.props.sdf_effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &sdf.getDrawBounds(
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
                if (text.sdf_texture_id) |sdf_texture_id| {
                    const padding = sdf.getSdfPadding(text.props.sdf_effects.items);
                    for (text.props.sdf_effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &sdf.getDrawBounds(
                                text.bounds,
                                padding,
                                null,
                            ),
                            text.getDrawUniform(effect, text.sdf_scale),
                            sdf_texture_id,
                        );
                    }
                    continue;
                }

                const is_typing_ui = state.tool == .Text and state.selected_asset_id.getPrim() == text.id;
                const selection_start = @min(texts.caret_position, texts.selection_end_position);
                const selection_end = @max(texts.caret_position, texts.selection_end_position);
                var vertex_triangles_buffer =
                    std.ArrayList(triangles.DrawInstance).init(allocator);
                const matrix = Matrix3x3.getMatrixFromRectangleNoScale(text.bounds);

                for (text.text_vertex.items, 0..) |vertex, i| {
                    if (vertex.char) |char| {
                        const ch_d = try fonts.get(0, char);

                        // char_details.request_size(
                        //     text.font_size,
                        //     sdf.getSdfPadding(text.props.sdf_effects.items),
                        // );
                        if (ch_d.sdf_texture_id) |sdf_texture_id| {
                            for (text.props.sdf_effects.items) |effect| {
                                web_gpu_programs.draw_shape(
                                    &vertex.getBounds(text.font_size * ch_d.max_ratio_padding_to_font_size, matrix),
                                    text.getDrawUniform(effect, ch_d.sdf_scale),
                                    sdf_texture_id,
                                );
                            }
                        }

                        if (is_typing_ui) {
                            const is_selection = selection_start != selection_end;

                            if (!is_selection and texts.caret_position == i) {
                                const caret_buffer = text.addCaretDrawVertex(
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
                if (texts.caret_position == text.text_vertex.items.len) {
                    const position =
                        if (text.text_vertex.getLastOrNull()) |last_vertex|
                            last_vertex.relative_bounds[2].toPoint()
                        else
                            types.Point{
                                .x = 0,
                                .y = -text.font_size * text.line_height,
                            };
                    const caret_buffer = text.addCaretDrawVertex(
                        position,
                    );
                    if (caret_buffer) |buffer| {
                        try vertex_triangles_buffer.appendSlice(&buffer);
                    }
                }

                if (is_typing_ui and vertex_triangles_buffer.items.len > 0) {
                    web_gpu_programs.draw_triangle(vertex_triangles_buffer.items);
                }
            },
        }
    }

    drawProjectBoundary(); // TODO: once we support strokes for triangles, we should use it here wit transparent fill

    if (state.tool == .None or state.tool == .Text) {
        try drawBorder(allocator);
    }

    if (state.tool == Tool.DrawShape or state.tool == Tool.EditShape) {
        const hover_point_id = state.hovered_asset_id;

        if (getSelectedShape()) |shape| {
            const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
            web_gpu_programs.draw_shape(
                &sdf.getDrawBounds(
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
                for (shape.props.sdf_effects.items) |effect| {
                    web_gpu_programs.pick_shape(
                        &shape.getPickBounds(),
                        shape.getPickUniform(effect),
                        shape.sdf_texture_id,
                    );
                }
            },
            .text => |text| {
                // if text selection is activ,e then render only selected text
                if (state.action == .TextSelection and state.selected_asset_id.getPrim() != text.id) continue;

                var triangles_buffer = std.ArrayList(triangles.PickInstance).init(std.heap.page_allocator);
                const matrix = Matrix3x3.getMatrixFromRectangleNoScale(text.bounds);
                const overflow_size =
                    if (state.action == .TextSelection)
                        300 * shared.render_scale
                    else
                        0.0;

                const text_width = text.bounds[1].distance(text.bounds[0]);
                const text_height = text.bounds[3].distance(text.bounds[0]);

                // above text area
                const area_above_text_buffer = rects.getPickVertexData(
                    matrix,
                    -overflow_size,
                    0,
                    text_width + 2 * overflow_size,
                    overflow_size,
                    0.0,
                    .{ text.id, 1, 0, 0 },
                );
                try triangles_buffer.appendSlice(&area_above_text_buffer);

                // below text area
                const area_below_text_buffer = rects.getPickVertexData(
                    matrix,
                    -overflow_size,
                    -text_height,
                    text_width + 2 * overflow_size,
                    -overflow_size,
                    0.0,
                    .{ text.id, text.text_vertex.items.len + 1, 0, 0 },
                );
                try triangles_buffer.appendSlice(&area_below_text_buffer);

                var next_char_is_first_in_line = true;
                for (text.text_vertex.items, 0..) |vertex, index| {
                    const half_width = (vertex.relative_bounds[1].x - vertex.origin.x) / 2;
                    if (half_width > consts.EPSILON) {
                        const valid_pick_index = index + 1; // pick = 0 -> no selection
                        // left part of the char
                        const left_additional_offset =
                            if (next_char_is_first_in_line) overflow_size else 0.0;
                        try triangles_buffer.appendSlice(&rects.getPickVertexData(
                            matrix,
                            vertex.origin.x - left_additional_offset,
                            vertex.origin.y,
                            half_width + left_additional_offset,
                            text.line_height * text.font_size,
                            0.0,
                            .{ text.id, valid_pick_index, 0, 0 },
                        ));

                        // right part of the char
                        const right_additional_offset =
                            if (vertex.last_in_line) overflow_size else 0.0;
                        try triangles_buffer.appendSlice(&rects.getPickVertexData(
                            matrix,
                            vertex.origin.x + half_width,
                            vertex.origin.y,
                            half_width + right_additional_offset,
                            text.line_height * text.font_size,
                            0.0,
                            .{ text.id, valid_pick_index + 1, 0, 0 },
                        ));

                        next_char_is_first_in_line = vertex.last_in_line;
                    }
                }

                if (triangles_buffer.items.len > 0) {
                    web_gpu_programs.pick_triangle(triangles_buffer.items);
                }
                triangles_buffer.deinit();
            },
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
        if (state.assets.get(state.selected_asset_id.getPrim())) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
                .text => |text| text.bounds,
            };
            var vertex_buffer: [TransformUI.PICK_TRIANGLE_INSTANCES]triangles.PickInstance = undefined;
            TransformUI.getPickVertexData(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES], points);
            web_gpu_programs.pick_triangle(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES]);
        }
    }
}

pub fn resetAssets(new_assets: []const AssetSerialized, with_snapshot: bool) !void {
    on_asset_update_cb = null;
    shapes.resetState();
    state.assets.clearAndFree();

    for (new_assets) |asset| {
        switch (asset) {
            .img => |img| {
                try addImage(img.id, img.points, img.texture_id);
            },
            .shape => |shape| {
                _ = try addShape(
                    shape.id,
                    shape.paths,
                    shape.bounds,
                    shape.props,
                    shape.sdf_texture_id,
                    shape.cache_texture_id,
                );
            },
            .text => |text| {
                _ = try addText(
                    text.id,
                    text.content orelse "",
                    text.bounds,
                    text.font_size,
                    text.props,
                );
            },
        }
    }

    if (!state.assets.contains(state.selected_asset_id.getPrim())) {
        try updateSelectedAsset(AssetId{});
    }
    on_asset_update_cb = original_on_asset_update_cb;
    try checkAssetsUpdate(with_snapshot);
}

pub fn deinitState() void {
    var it = state.assets.iterator();
    while (it.next()) |entry| {
        switch (entry.value_ptr.*) {
            .img => {},
            .shape => |*shape| shape.deinit(),
            .text => {},
        }
    }
    state.assets.clearAndFree();
    UI.deinit();
    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = &.{};
    state.selected_asset_id = AssetId{};
    state.hovered_asset_id = AssetId{};
    next_asset_id = ASSET_ID_MIN;
    web_gpu_programs = undefined;
    on_asset_update_cb = undefined;
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

var ticks: u32 = 0; // it's like a time, but always increases by 1, used for performance optimizations
pub fn tick(now: f32) void {
    ticks +%= 1;
    shared.setTime(now);
}

pub fn toggleSharedTextEffects() void {
    if (getSelectedText()) |text| {
        if (text.sdf_texture_id != null) {
            text.sdf_texture_id = null;
        } else {
            text.sdf_texture_id = create_sdf_texture();
            text.is_sdf_outdated = true;
        }
    }
}

test "reset_assets does not call the real update callback" {
    // Setup initial state
    initState(100, 100);
    // Ensure state is cleaned up after the test
    defer deinitState();

    // Define a mock callback function locally, with its own static state.
    const MockCallback = struct {
        // This static variable will hold the state for our mock.
        // It's reset to false before each test run.
        var was_called: bool = false;

        fn assets_update(_: []const images.Serialized) void {
            // Modify the static variable within the struct.
            was_called = true;
        }

        fn assets_selection(_: u32) void {}
    };

    // Connect our mock callback. This is the "real" callback for this test.
    connectOnAssetUpdateCallback(MockCallback.assets_update);
    connectOnAssetSelectionCallback(MockCallback.assets_selection);

    // Call the function we are testing
    const initial_assets = [_]images.Serialized{.{
        .points = [_]types.PointUV{
            types.PointUV{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
            types.PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
            types.PointUV{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
            types.PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
        },
        .texture_id = 1,
        .id = 123,
    }};
    resetAssets(&initial_assets, false);

    // for the duration of resetAssets, the update callback should NOT be called
    try std.testing.expect(!MockCallback.was_called);
}
