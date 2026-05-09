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
const chars = @import("texts/chars.zig");
const assets = @import("assets.zig");
const webgpu_glue = @import("webgpu_glue.zig");
const computeShape = @import("compute_shape.zig").computeShape;

pub const INFINITE_DISTANCE = consts.INFINITE_DISTANCE;
pub const DEFAULT_FONT_ID = fonts.DEFAULT_FONT_ID;

pub fn connectWebGpuPrograms(programs: *const webgpu_glue.WebGpuProgramsInput) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    webgpu_glue.connect(programs);
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

const MIN_NEW_CONTROL_POINT_DISTANCE = 10.0; // Minimum distance to consider a new control point

var state = types.State{
    .width = 0,
    .height = 0,
    .hovered_asset_id = AssetId{},
    .action = ActionType.None,
    .tool = Tool.None,
    .selection = .{ null, null },
    .selected_assets = .empty,
    .selected_asset_copied = false, // used when move starts with alt, so we mark that copy was already done
    .action_pointer_offset = types.Point{ .x = 0.0, .y = 0.0 }, // indicates pointer position when action has started, useful for transformatiosn with ctrl/shift
    .init_action_bounds = undefined, // useful to perform constrained operations (like moving pointer with shortcut to maintin aspect ratio)
    .redraw_needed = true,
};

pub fn initState(width: f32, height: f32, texture_max_size: f32, max_buffer_size: f32, is_test: bool) !void {
    shared.texture_max_size = texture_max_size;
    shared.max_buffer_size = max_buffer_size;
    shared.is_test = is_test;
    state.width = width;
    state.height = height;
    state.redraw_needed = true;
    assets.init();
    UI.init();
    fonts.init();
}

pub fn updateRenderScale(zoom: f32, pixel_density: f32) !void {
    state.redraw_needed = true;
    shared.render_scale = 1 / (pixel_density * zoom);
    shared.ui_scale = pixel_density / zoom;
    shared.pixel_density = pixel_density;

    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);
                const new_sdf_dims = sdf_drawing.getTexture(
                    shape.sdf_tex.id,
                    shape.bounds,
                    sdf_padding,
                    1.0,
                );

                if (new_sdf_dims.isBiggerThan(shape.sdf_tex)) {
                    shape.sdf_tex.is_outdated = true;
                }
            },
            .text => |*text| {
                try chars.requestCharsSdfs(text.*);

                if (text.is_sdf_shared) {
                    const sdf_dims = sdf_drawing.getTexture(
                        text.sdf_tex.id,
                        text.bounds,
                        sdf_drawing.getSdfPadding(text.effects.items),
                        1,
                    );

                    if (sdf_dims.isBiggerThan(text.sdf_tex)) {
                        text.sdf_tex.is_outdated = true;
                    }
                }
            },
        }
    }

    // We don't update font here because we would need to know what fonts/chars are still in use!
    // so It's better to update them in render draw
}

pub fn removeAsset() !void {
    state.redraw_needed = true;
    snapshots.triggerNewSnapshot(true, true);

    if ((state.tool == .DrawShape or state.tool == .EditShape) and
        assets.selected_asset_id.isSec() and
        assets.selected_asset_id.isTert())
    {
        if (assets.getSelectedShape()) |shape| {
            if (shape.paths.items.len > assets.selected_asset_id.getSec()) {
                var active_path = &shape.paths.items[assets.selected_asset_id.getSec()];
                const point_index = assets.selected_asset_id.getTert();
                if (active_path.points.items.len > point_index) {
                    _ = active_path.points.orderedRemove(point_index);
                    // TODO: split shape into two paths if they are not connected anymore
                    // handle case when that was last point
                    return;
                }
            }
        }
    }

    assets.removeSelected();
    try setSelectedAsset(AssetId{});
}

pub fn onUpdatePick(id: [4]u32) void {
    if (state.action != .Transform and !state.hovered_asset_id.equal(id)) {
        state.redraw_needed = true;
        state.hovered_asset_id = AssetId.fromArray(id);
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

fn setSelectedAsset(id: AssetId) !void {
    try commitChanges();
    assets.selected_asset_id = id;
    js_glue.onAssetSelection(id.serialize());
}

pub fn updateTextContent(
    input_content: []const u8,
    selection_start: usize,
    selection_end: usize,
) !texts.ComputeTextResult {
    const option_text = assets.getSelectedText();
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

pub fn addText() !void {
    const width = 300.0;
    const font_size = 72.0;
    const line_height = 1.0;

    const new_text = try assets.createText(
        (state.width - width) / 2.0,
        (state.height + font_size * line_height) / 2.0,
        width,
        font_size,
        line_height,
    );
    try setSelectedAsset(AssetId{ ._prim = new_text.id });
}

// @param auto_select - whether to select asset on pointer down, useufl for dekstop users
pub fn onPointerDown(x: f32, y: f32) !void {
    state.redraw_needed = true;

    if (state.tool == .Text) {
        try setSelectedAsset(state.hovered_asset_id);

        if (assets.getSelectedText()) |text| {
            enable_typing(text.content);

            if (state.hovered_asset_id.isSec()) {
                assets.selected_asset_id.setSec(state.hovered_asset_id.getSec());

                const caret_index = state.hovered_asset_id.getSec();
                setCaretPosition(caret_index, caret_index);
                update_text_selection(caret_index, caret_index);
            }

            state.action = .TextSelection;
        }
    } else if (state.tool == Tool.DrawShape) {
        if (assets.getSelectedShape() == null) {
            const id = try assets.createShape();
            try setSelectedAsset(AssetId{ ._prim = id });
        }

        if (assets.getSelectedShape()) |shape| {
            try shape.addPointStart(
                std.heap.page_allocator,
                types.Point{ .x = x, .y = y },
            );
            return;
        } else {
            @panic("Selected shape asset should be present at this point");
        }
    } else {
        if (!state.hovered_asset_id.isPrim()) {
            state.selection = .{
                types.Point{ .x = x, .y = y },
                types.Point{ .x = x, .y = y },
            };
            // let's start selection
            return;
        }

        if (state.tool == Tool.EditShape) {
            // should not be accessible on mobile, that's why selection happens with pointer down
            if (state.hovered_asset_id.isPrim()) {
                try setSelectedAsset(state.hovered_asset_id);
            }
        }

        if (state.hovered_asset_id.getPrim() >= consts.ASSET_ID_MIN and
            state.tool == .None and
            state.action == .None)
        {
            // This standard for desktop, not sure if gonna work well with mobile
            try setSelectedAsset(state.hovered_asset_id);
        }

        if (assets.getSelectedAsset()) |asset| {
            const bounds = asset.getBounds();
            state.init_action_bounds = bounds;

            if (transform_ui.isTransformUi(state.hovered_asset_id.getPrim())) {
                state.action = .Transform;
            } else if (assets.selected_asset_id.getPrim() >= consts.ASSET_ID_MIN and
                assets.selected_asset_id.getPrim() == state.hovered_asset_id.getPrim())
            {
                state.selected_asset_copied = false;
                state.action = .Move;
                state.action_pointer_offset = types.Point{
                    .x = x - bounds[0].x,
                    .y = y - bounds[0].y,
                };
            }
        }
    }
}

pub fn onPointerUp() !void {
    state.redraw_needed = true;
    state.selection = .{ null, null };

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
        if (assets.getSelectedShape()) |shape| {
            shape.onReleasePointer();
        }
    } else if (state.tool == Tool.EditShape) {
        snapshots.triggerNewSnapshot(true, true);
        if (assets.getSelectedShape()) |shape| {
            shape.onReleasePointer();
        }
        // to remove sec, third, quat fields
        assets.selected_asset_id = AssetId{ ._prim = assets.selected_asset_id.getPrim() };
    } else if (state.tool == Tool.Text) {
        state.action = .None;
    }
}

pub fn onPointerMove(x: f32, y: f32, constrained: bool, alt_key: bool) !void {
    if (state.tool == Tool.DrawShape) {
        if (assets.getSelectedShape()) |shape| {
            state.redraw_needed = true;
            shape.updatePointPreview(types.Point{ .x = x, .y = y });
        }
        return;
    }

    if (state.tool == Tool.Text and state.action == .TextSelection) {
        if (assets.getSelectedText() != null) {
            if (state.hovered_asset_id.getPrim() == assets.selected_asset_id.getPrim()) {
                if (state.hovered_asset_id.isSec() and assets.selected_asset_id.isSec()) {
                    state.redraw_needed = true;

                    const new_caret_index = state.hovered_asset_id.getSec();
                    const curr_caret_index = assets.selected_asset_id.getSec();

                    const start = @min(new_caret_index, curr_caret_index);
                    const end = @max(new_caret_index, curr_caret_index);
                    setCaretPosition(start, end);
                    update_text_selection(start, end);
                }
            }
        }
        return;
    }

    if (state.selection[0]) |selection_start| {
        const pointer = types.Point{ .x = x, .y = y };
        const distance = selection_start.distance(pointer);

        // 1.0 should depend on zoom probably, it shoudl be value relative to the user, not absolute
        if (distance > 1.0) {
            state.selection[1] = pointer;
            state.redraw_needed = true;

            var selected_assets: std.AutoHashMapUnmanaged(u32, void) = .empty;

            const min_x = @min(selection_start.x, pointer.x);
            const max_x = @max(selection_start.x, pointer.x);
            const min_y = @min(selection_start.y, pointer.y);
            const max_y = @max(selection_start.y, pointer.y);

            var iter = assets.getIter();
            while (iter.next()) |entry| {
                const bounds = entry.value_ptr.*.getBounds();
                for (bounds) |b| {
                    if (b.x > min_x and b.x < max_x and b.y > min_y and b.y < max_y) {
                        try selected_assets.put(std.heap.page_allocator, entry.key_ptr.*, {});
                        break;
                    }
                }
            }

            state.selected_assets.deinit(std.heap.page_allocator);
            state.selected_assets = selected_assets;
        }

        return;
    }

    if (state.tool == Tool.EditShape) {
        if (assets.selected_asset_id.isTert()) {
            if (assets.getSelectedShape()) |shape| {
                state.redraw_needed = true;

                const matrix = Matrix3x3.getMatrixFromRectangle(shape.bounds);
                const pointer = matrix.inverse().get(types.Point{ .x = x, .y = y });

                const path = shape.paths.items[assets.selected_asset_id.getSec()];
                const points = path.points.items;
                const i = assets.selected_asset_id.getTert(); // point index

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
                shape.sdf_tex.is_outdated = true;
            }
        }
        return;
    }

    const selected_asset = assets.getSelectedAsset() orelse return;

    const asset = if (state.action == .Move and !state.selected_asset_copied and alt_key) b: {
        state.selected_asset_copied = true;
        const cloned_asset = try assets.clone(selected_asset.*);
        break :b cloned_asset;
    } else selected_asset;

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
                alt_key,
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

                    const is_text_area_enabled = state.tool == .Text and assets.selected_asset_id.isSec();
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
    if (state.tool == .None and assets.getSelectedText() != null) {
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
        if (assets.getSelectedShape()) |shape| {
            shape.updateControlPointPreview(null);
        }

        shapes.resetState();
    }

    const is_text_area_enabled = state.tool == .Text and assets.selected_asset_id.isSec();
    if (is_text_area_enabled) {
        disable_typing();
        caret.position = 0;
        caret.selection_end_position = 0;
    }
}

fn drawBorder(allocator: std.mem.Allocator) !void {
    var triangle_vertex_data = std.ArrayList(triangles.DrawInstance).init(allocator);
    var ui_vertex_data = std.ArrayList(UI.DrawVertex).init(allocator);

    if (state.selection[0]) |selection_start| {
        if (state.selection[1]) |selection_end| {
            var buffer: [2 * 4]triangles.DrawInstance = undefined;

            const min_x = @min(selection_start.x, selection_end.x);
            const max_x = @max(selection_start.x, selection_end.x);
            const min_y = @min(selection_start.y, selection_end.y);
            const max_y = @max(selection_start.y, selection_end.y);

            const points = [_]types.Point{
                .{ .x = min_x, .y = min_y },
                .{ .x = max_x, .y = min_y },
                .{ .x = max_x, .y = max_y },
                .{ .x = min_x, .y = max_y },
            };

            const color = [_]u8{ 50, 200, 50, 255 }; // gray color

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

            webgpu_glue.draw_triangle(&buffer);

            var iter = assets.getIter();
            while (iter.next()) |entry| {
                if (state.selected_assets.contains(entry.key_ptr.*)) {
                    try triangle_vertex_data.appendSlice(
                        &transform_ui.getBorderDrawVertex(entry.value_ptr.*, true),
                    );
                }
            }

            if (triangle_vertex_data.items.len > 0) {
                webgpu_glue.draw_triangle(triangle_vertex_data.items);
            }
            return;
        }
    }

    if (state.hovered_asset_id.getPrim() != assets.selected_asset_id.getPrim()) {
        if (assets.getAsset(state.hovered_asset_id)) |asset| {
            try triangle_vertex_data.appendSlice(
                &transform_ui.getBorderDrawVertex(asset, false),
            );
        }
    }

    if (assets.getSelectedAsset()) |asset| {
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
        webgpu_glue.draw_triangle(triangle_vertex_data.items);
    }

    try UI.draw(ui_vertex_data.items);
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
    webgpu_glue.draw_triangle(&buffer);
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

    webgpu_glue.draw_triangle(&buffer);
}

pub fn updateCache() void {
    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                if (shape.props.blur) |blur| {
                    // TODO: refactor this, reuse functions from sdf_drawing
                    if (!shape.outdated_cache) continue;

                    const cache_texture_id: u32 = if (shape.cache_texture_id) |id| id else b: {
                        const id = js_glue.createCacheTexture();
                        shape.cache_texture_id = id;
                        break :b id;
                    };

                    const padding_world = sdf_drawing.getSdfPadding(shape.effects.items);
                    const bounds = sdf_drawing.getBoundsWithPadding(
                        shape.bounds,
                        padding_world,
                        1 / shared.render_scale,
                        // WARNING: here 1px safety padding changes into 1/shared.render_scale
                        shape.getFilterMargin(),
                        consts.POINT_ZERO,
                    );
                    // NOTE: on 99% those calcualtions are not accurate because do nto account sdf_tex.round_err
                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
                    const size, const sigma, const cache_scale = texture_size.get_safe_blur_dims(
                        init_width,
                        bounds,
                        blur,
                    );

                    // if (size.w < consts.MIN_TEXTURE_SIZE or size.h < consts.MIN_TEXTURE_SIZE) continue;
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

                    if (shape.sdf_tex.valid) {
                        // addiitonal guard, if shape was just loaded andhas invaldi boudnign box, then has the default sdf_tex, with empty slice as points,
                        // what will cause empty buffer error for webgpu
                        for (shape.effects.items) |effect| {
                            webgpu_glue.draw_shape(
                                &vertex_bounds,
                                shape.getDrawUniform(effect),
                                shape.sdf_tex.id,
                                shape.sdf_tex.points,
                                shape.sdf_tex.arc_lengths,
                                shape.sdf_tex.max_distances,
                            );
                        }
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

                    webgpu_glue.draw_blur(
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

pub fn computePhase() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var fonts_iter = fonts.fonts.iterator();

    while (fonts_iter.next()) |font_entry| {
        var font = font_entry.value_ptr.*;
        var char_iter = font.chars.iterator();

        while (char_iter.next()) |char_details_entry| {
            var ch_d = char_details_entry.value_ptr.*;

            if (ch_d.sdf_tex) |*ch_sdf_tex| {
                const unknown_size = utils.equalF32(ch_d.font_size, 0);
                if (!ch_sdf_tex.is_outdated or unknown_size) continue;

                const ch_w = ch_d.font_size * ch_d.width;
                const ch_h = ch_d.font_size * ch_d.height;

                const bounds = utils.createBounds(ch_w, ch_h);
                const padding = ch_d.font_size * ch_d.*.max_ratio_padding_to_font_size;

                var deep_copy_paths = try allocator.alloc([]types.Point, ch_d.paths.len);
                for (ch_d.paths, 0..) |slice, i| {
                    deep_copy_paths[i] = try allocator.dupe(types.Point, slice);
                }

                for (deep_copy_paths) |path| {
                    for (path) |*point| {
                        if (path_utils.isStraightLineHandle(point.*)) {
                            continue;
                        }
                        point.x *= ch_d.font_size;
                        point.y *= ch_d.font_size;
                    }
                }

                ch_sdf_tex.deinit();

                const new_sdf_tex = try computeShape(
                    ch_sdf_tex.id,
                    bounds,
                    padding,
                    deep_copy_paths,
                    consts.SDF_RESIZE_STEP,
                );

                ch_d.sdf_tex = new_sdf_tex;
                ch_d.viewport_font_size = consts.SDF_RESIZE_STEP * ch_d.font_size / shared.render_scale;
            }
        }
    }

    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                const is_throttle_event = shared.ticks % 5 == 0;
                // in the future we might do throttle depends on the number of selected shapes
                // also instead of ticks we can do (ticks + shape.id) to avoid making all updates at once
                const do_update = shape.sdf_tex.is_outdated or (shape.should_update_sdf and is_throttle_event);
                if (!do_update) continue;

                const option_paths = try shape.getRelativePaths(allocator);
                if (option_paths) |paths| {
                    const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);

                    shape.sdf_tex.deinit();

                    shape.sdf_tex = try computeShape(
                        shape.sdf_tex.id,
                        shape.bounds,
                        sdf_padding,
                        paths,
                        consts.SDF_RESIZE_STEP,
                    );

                    shape.outdated_cache = true;
                }

                shape.should_update_sdf = false;
            },

            // 13.006909 20.819618
            // 100000000000 0
            // 100000000000 0
            // 11.557464 15.901351
            // 11.557464 15.901351
            // 6.8526325 19.11583
            // 2.252256 22.539345
            // 3.3104331 25.667856
            // 3.3104331 25.667856
            // 4.198273 28.29274
            // 9.876935 28.935127
            // 15.624522 29.288727
            // 15.624522 29.288727
            // 13.805719 25.242552
            // 13.006909 20.819618
            // 13.006909 20.819618
            // 15.624522 29.288727
            // 17.763805 34.047844
            // 21.314205 38.28574
            // 26.635637 34.192207
            // 26.635637 34.192207
            // 32.466988 29.706656
            // 23.973047 29.80234
            // 15.624522 29.288727
            // 11.557464 15.901351
            // 100000000000 0
            // 100000000000 0
            // 8.72936 6.305017
            // 8.72936 6.305017
            // 10.438309 1.5942386
            // 17.61399 2.4549937
            // 20.26472 6.999194
            // 20.26472 6.999194
            // 21.627316 9.335051
            // 16.533957 12.501266
            // 11.557464 15.901351

            .text => |*text| {
                if (text.is_sdf_shared) {
                    if (!text.sdf_tex.is_outdated) continue;

                    if (!fonts.isReady) continue;

                    const text_padding = sdf_drawing.getSdfPadding(text.effects.items);

                    text.sdf_tex.deinit();
                    text.sdf_tex = sdf_drawing.getTexture(
                        text.sdf_tex.id,
                        text.bounds,
                        text_padding,
                        consts.SDF_RESIZE_STEP,
                    );

                    const compute_depth_texture_id = js_glue.createDisposableComputeDepthTexture(
                        @intFromFloat(text.sdf_tex.size.w),
                        @intFromFloat(text.sdf_tex.size.h),
                    );

                    webgpu_glue.start_combine_sdf(
                        text.sdf_tex.id,
                        compute_depth_texture_id,
                        @intFromFloat(text.sdf_tex.size.w),
                        @intFromFloat(text.sdf_tex.size.h),
                    );

                    const bounds_height = text.bounds[0].distance(text.bounds[3]);
                    const matrix = Matrix3x3.translation(
                        text_padding,
                        bounds_height + text_padding,
                    );

                    var all_points = std.ArrayList(types.Point).init(std.heap.page_allocator);
                    defer all_points.deinit();

                    for (text.text_vertex.items) |vertex| {
                        if (vertex.char) |char| {
                            const ch_d = try fonts.get(text.typo_props.font_family_id, char);

                            if (ch_d.sdf_tex) |char_sdf_tex| {
                                // Should always work alike renderDraw when each character is rendered separately form own SDFs

                                const padding_world = text.typo_props.font_size * ch_d.max_ratio_padding_to_font_size;
                                const bounds_texel = vertex.getDrawBounds(
                                    padding_world,
                                    char_sdf_tex,
                                    matrix,
                                    text.sdf_tex.scale,
                                );

                                const texel_placement = webgpu_glue.CombineSdfUniform{
                                    .x = bounds_texel[4].x + consts.SDF_SAFE_PADDING,
                                    .y = bounds_texel[4].y + consts.SDF_SAFE_PADDING,
                                    .width = bounds_texel[4].distance(bounds_texel[2]),
                                    .height = bounds_texel[4].distance(bounds_texel[0]),
                                    .initial_t = @as(f32, @floatFromInt(all_points.items.len / 4)),
                                };

                                const transformed_points = try std.heap.page_allocator.dupe(types.Point, char_sdf_tex.points);
                                const scale_x = texel_placement.width / char_sdf_tex.size.w;
                                const scale_y = texel_placement.height / char_sdf_tex.size.h;
                                for (transformed_points) |*p| {
                                    p.x = texel_placement.x + p.x * scale_x;
                                    p.y = texel_placement.y + p.y * scale_y;
                                }

                                webgpu_glue.combine_sdf(
                                    text.sdf_tex.id,
                                    char_sdf_tex.id,
                                    compute_depth_texture_id,
                                    texel_placement,
                                    transformed_points,
                                );

                                try all_points.appendSlice(transformed_points);
                            }
                        }
                    }

                    std.heap.page_allocator.free(text.sdf_tex.points);
                    text.sdf_tex.points = try all_points.toOwnedSlice();
                    text.sdf_tex.valid = text.sdf_tex.points.len > 0;

                    webgpu_glue.finish_combine_sdf();
                }
            },
        }
    }
}

pub fn renderDraw(is_ui_hidden: bool) !void {
    state.redraw_needed = false;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    drawProjectBackground();

    // use this array list to collect all items that should be drawn on the very top
    var vertex_triangles_buffer =
        std.ArrayList(triangles.DrawInstance).init(allocator);

    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: [6]types.PointUV = undefined;
                img.getRenderVertexData(&vertex_data);
                webgpu_glue.draw_texture(&vertex_data, img.texture_id);
            },
            .shape => |*shape| {
                if (shape.cache_texture_id) |cache_texture_id| {
                    const bounds = shape.getDrawBounds(true);
                    webgpu_glue.draw_texture(
                        &bounds,
                        cache_texture_id,
                    );
                } else {
                    const bounds = shape.getDrawBounds(false);
                    if (shape.sdf_tex.valid) {
                        for (shape.effects.items) |effect| {
                            webgpu_glue.draw_shape(
                                &bounds,
                                shape.getDrawUniform(effect),
                                shape.sdf_tex.id,
                                shape.sdf_tex.points,
                                shape.sdf_tex.arc_lengths,
                                shape.sdf_tex.max_distances,
                            );
                        }
                    }
                }
            },
            .text => |*text| {
                if (!fonts.isReady) continue;

                const is_typing_ui = !is_ui_hidden and state.tool == .Text and assets.selected_asset_id.getPrim() == text.id;

                if (text.is_sdf_shared) {
                    const bounds = text.getDrawBounds();
                    for (text.effects.items) |effect| {
                        webgpu_glue.draw_shape(
                            &bounds,
                            text.getDrawUniform(effect, text.sdf_tex.scale),
                            text.sdf_tex.id,
                            text.sdf_tex.points,
                            text.sdf_tex.arc_lengths,
                            text.sdf_tex.max_distances,
                        );
                    }

                    if (!is_typing_ui) continue;
                }

                const selection_start = @min(caret.position, caret.selection_end_position);
                const selection_end = @max(caret.position, caret.selection_end_position);
                const matrix = Matrix3x3.getMatrixFromRectangleNoScale(text.bounds);

                for (text.text_vertex.items, 0..) |vertex, i| {
                    if (vertex.char) |char| {
                        if (!text.is_sdf_shared) {
                            const ch_d = try fonts.get(text.typo_props.font_family_id, char);

                            if (ch_d.sdf_tex) |char_sdf_tex| {
                                // Should always work alike computePhase combinign chars sdf into text sdf
                                const char_sdf_viewport_font_size = ch_d.font_size * char_sdf_tex.scale;
                                const sdf_scale = char_sdf_viewport_font_size / text.typo_props.font_size;

                                const bounds = vertex.getDrawBounds(
                                    text.typo_props.font_size * ch_d.max_ratio_padding_to_font_size,
                                    char_sdf_tex,
                                    matrix,
                                    1.0,
                                );

                                for (text.effects.items) |effect| {
                                    webgpu_glue.draw_shape(
                                        &bounds,
                                        text.getDrawUniform(effect, sdf_scale),
                                        char_sdf_tex.id,
                                        char_sdf_tex.points,
                                        char_sdf_tex.arc_lengths,
                                        char_sdf_tex.max_distances,
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
                if (is_typing_ui and caret.position == text.text_vertex.items.len and caret.isCaretShown()) {
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

        if (assets.getSelectedShape()) |shape| {
            if (shape.sdf_tex.valid) {
                webgpu_glue.draw_shape(
                    &shape.getDrawBounds(false),
                    shape.getSkeletonUniform(),
                    shape.sdf_tex.id,
                    shape.sdf_tex.points,
                    shape.sdf_tex.arc_lengths,
                    shape.sdf_tex.max_distances,
                );
            }

            const hover_id = if (shape.id == hover_point_id.getPrim()) hover_point_id else null;
            const vertex_data = try shape.getSkeletonDrawVertexData(
                allocator,
                hover_id,
                state.tool == Tool.DrawShape,
            );
            webgpu_glue.draw_triangle(vertex_data);
        }
    }

    if (vertex_triangles_buffer.items.len > 0) {
        webgpu_glue.draw_triangle(vertex_triangles_buffer.items);
    }
}

pub fn renderPick() !void {
    if (state.tool == Tool.DrawShape) {
        return;
    }

    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: [6]images.PickVertex = undefined;
                img.getPickVertexData(&vertex_data);

                webgpu_glue.pick_texture(&vertex_data, img.texture_id);
            },
            .shape => |shape| {
                const bounds = shape.getPickBounds();

                if (shape.sdf_tex.valid) {
                    for (shape.effects.items) |effect| {
                        webgpu_glue.pick_shape(
                            &bounds,
                            shape.getPickUniform(effect),
                            shape.sdf_tex.id,
                            shape.sdf_tex.points,
                            shape.sdf_tex.arc_lengths,
                            shape.sdf_tex.max_distances,
                        );
                    }
                }
            },
            .text => |text| {
                if (state.action == .TextSelection) continue; // while selecting text I need only active/selected text asset

                // if there is any text selected, render pick for only that text(at the end to make sure selected text is a priority)
                if (state.tool == Tool.Text and assets.selected_asset_id.getPrim() == text.id) continue;

                const buffer = try text.addPickVertex(
                    std.heap.page_allocator,
                    0,
                );
                webgpu_glue.pick_triangle(buffer);
                std.heap.page_allocator.free(buffer);
            },
        }
    }

    if (state.tool == Tool.Text) {
        if (assets.getSelectedText()) |text| {
            const overflow_margin_factor = if (state.action == .TextSelection) 300 * shared.ui_scale else 0;
            const buffer = try text.addPickVertex(
                std.heap.page_allocator,
                overflow_margin_factor,
            );
            webgpu_glue.pick_triangle(buffer);
            std.heap.page_allocator.free(buffer);
        }
    }

    if (state.tool == Tool.EditShape) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        if (assets.getSelectedShape()) |shape| {
            const vertex_data = try shape.getSkeletonPickVertexData(allocator);
            webgpu_glue.pick_triangle(vertex_data);
        }
    }

    if (state.tool == Tool.None) {
        if (assets.getSelectedAsset()) |asset| {
            const bounds = asset.getBounds();
            var vertex_buffer: [transform_ui.PICK_TRIANGLE_INSTANCES]triangles.PickInstance = undefined;
            transform_ui.getPickVertexData(vertex_buffer[0..transform_ui.PICK_TRIANGLE_INSTANCES], bounds);
            webgpu_glue.pick_triangle(vertex_buffer[0..transform_ui.PICK_TRIANGLE_INSTANCES]);
        }
    }
}

pub fn setSnapshot(snapshot: snapshots.ProjectSnapshot, with_snapshot: bool, commit: bool) !void {
    state.redraw_needed = true;
    state.width = snapshot.width;
    state.height = snapshot.height;

    snapshots.skip_snapshot = true;
    shapes.resetState();

    try assets.resetTo(snapshot.assets);

    // deselect asset if it's removed (was not present in the snapshot)
    if (!assets.hasSelectedAsset()) {
        try setSelectedAsset(AssetId{});
    }
    snapshots.skip_snapshot = false;
    snapshots.triggerNewSnapshot(with_snapshot, commit);
}

pub fn deinitState() !void {
    state = types.State{
        .width = 0,
        .height = 0,
        .hovered_asset_id = AssetId{},
        .action = ActionType.None,
        .tool = Tool.None,
        .selection = .{ null, null },
        .selected_assets = .empty,
        .selected_asset_copied = false,
        .action_pointer_offset = types.Point{ .x = 0.0, .y = 0.0 },
        .init_action_bounds = undefined,
        .redraw_needed = true,
    };

    assets.selected_asset_id = AssetId{};
    try assets.resetTo(&.{}); // reinit with empty snapshot to deinit all assets
    UI.deinit();
    snapshots.deinit();
    webgpu_glue.deinit();
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
    try UI.generateUiElementsSdf();
}

pub fn setTool(tool: Tool) !void {
    try commitChanges();
    state.tool = tool;

    if (tool == .Text) {
        if (assets.getSelectedText()) |text| {
            enable_typing(text.content);
        }
    }
}

// returns bool indicating if an update in drawing is needed
var lastIsCaretShown = false;
pub fn tick(now: f32) !bool {
    shared.tick(now);
    try snapshots.loop(state);

    if (!state.redraw_needed and state.tool == .Text and assets.getSelectedText() != null) {
        const isCaretShown = caret.isCaretShown();

        if (isCaretShown != lastIsCaretShown) {
            lastIsCaretShown = isCaretShown;
            return true;
        }
    }

    return state.redraw_needed;
}

pub fn setSelectedAssetTypoProps(serialized: typography_props.Serialized, commit: bool) !void {
    if (assets.getSelectedText()) |text| {
        const new_typo_props = typography_props.deserialize(serialized);
        text.typo_props = new_typo_props;

        const result = try text.computeText(0, 0);

        const is_text_area_enabled = state.tool == .Text and assets.selected_asset_id.isSec();

        if (is_text_area_enabled) {
            // although this should not really happen, if user changes font properties,
            // then it's not longer in typing tool in the textbox
            update_text_content(result.content);
            // new soft breaks might appear after font change
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn setSelectedAssetEffects(serialized_effects: []const sdf_effect.Serialized, commit: bool) !void {
    if (assets.getSelectedAsset()) |asset| {
        switch (asset.*) {
            .img => {},
            .shape => |*shape| {
                sdf_effect.deinit(shape.effects);
                shape.effects = try sdf_effect.deserialize(serialized_effects, std.heap.page_allocator);
                shape.sdf_tex.is_outdated = true;
            },
            .text => |*text| {
                sdf_effect.deinit(text.effects);
                text.effects = try sdf_effect.deserialize(serialized_effects, std.heap.page_allocator);

                try chars.requestCharsSdfs(text.*);

                if (text.is_sdf_shared) {
                    text.sdf_tex.is_outdated = true;
                }
            },
        }

        state.redraw_needed = true;
        snapshots.triggerNewSnapshot(true, commit);
    }
}

pub fn setSelectedAssetProps(props: asset_props.Props, commit: bool) !void {
    if (assets.getSelectedAsset()) |asset| {
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
    // TODO: code duplication with transform_ui

    if (assets.getSelectedAsset()) |asset| {
        switch (asset.*) {
            .img => |*img| {
                img.bounds = bounds;
            },
            .shape => |*shape| {
                shape.bounds = bounds;
                shape.should_update_sdf = true;
            },
            .text => |*text| {
                text.bounds = bounds;
                const result = try text.computeText(
                    caret.position,
                    caret.selection_end_position,
                );

                const is_text_area_enabled = state.tool == .Text and assets.selected_asset_id.isSec();
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

    var iterator = assets.getIter();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => {},
            .text => |*text| {
                // defualt font is used as fallback
                if (font_id == DEFAULT_FONT_ID or text.typo_props.font_family_id == font_id) {
                    state.redraw_needed = true;

                    const result = try text.computeText(0, 0);

                    const is_text_area_enabled = state.tool == .Text and assets.selected_asset_id.isSec();
                    if (is_text_area_enabled and text.id == assets.selected_asset_id.getPrim()) {
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
        assets.selected_asset_id = AssetId.fromArray(.{ assets.selected_asset_id.getPrim(), 0, 0, 0 });
        caret.position = 0;
        caret.selection_end_position = 0;
    }
}

pub fn invalidateCacheByProgram(program_id: u32) void {
    var iter = assets.getIter();
    while (iter.next()) |asset| {
        switch (asset.value_ptr.*) {
            .shape => |*shape| {
                for (shape.effects.items) |effect| {
                    switch (effect.fill) {
                        .program_id => |id| {
                            if (id == program_id) {
                                state.redraw_needed = true;
                                shape.outdated_cache = true;
                                snapshots.triggerNewSnapshot(true, false);
                                break;
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

// Invalidates cache for given asset ids
// Useful when a resource is ready to be rendered, e.g. image, font, program finished compiling
// but that resource loading did not trigger a change in asset serialized state
// so you have to explicitly invalidate cache to re-render with newest resource version
pub fn invalidateCache(ids: []const u32) void {
    for (ids) |id| {
        const assetId = AssetId.fromArray(.{ id, 0, 0, 0 });
        if (assets.getAssetPtr(assetId)) |asset| {
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

test {
    _ = @import("sdf/drawing.zig");
}
