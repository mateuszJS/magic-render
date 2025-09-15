const std = @import("std");
const types = @import("types.zig");
const images = @import("images.zig");
const lines = @import("lines.zig");
const Triangle = @import("triangle.zig");
const TransformUI = @import("transform_ui.zig");
const zigar = @import("zigar");
const shapes = @import("./shapes/shapes.zig");
const rects = @import("rects.zig");
const bounding_box = @import("shapes/bounding_box.zig");
const shared = @import("shared.zig");
const texture_size = @import("texture_size.zig");
const Utils = @import("utils.zig");
const PackedId = @import("shapes/packed_id.zig");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const PathUtils = @import("shapes/path_utils.zig");
const consts = @import("consts.zig");
const UI = @import("ui.zig");
const texts = @import("texts/texts.zig");
const sdf = @import("sdf/sdf.zig");
const fonts = @import("texts/fonts.zig");

const FillType = enum(u8) {
    Solid,
    LinearGradient,
    RadialGradient,
};

const WebGpuPrograms = struct {
    draw_texture: *const fn ([]const types.PointUV, u32) void,
    draw_triangle: *const fn ([]const Triangle.DrawInstance) void,
    compute_shape: *const fn ([]const types.Point, f32, f32, u32) void,
    draw_blur: *const fn (u32, u32, u32, u32, f32, f32) void,
    draw_shape: *const fn ([]const types.PointUV, sdf.DrawUniform, u32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
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

var on_asset_select_cb: *const fn (u32) void = undefined;
pub fn connectOnAssetSelectionCallback(cb: *const fn (u32) void) void {
    on_asset_select_cb = cb;
}

var create_sdf_texture: *const fn () u32 = undefined;
pub fn connectCreateSdfTexture(cb: *const fn () u32) void {
    create_sdf_texture = cb;
}

pub const SerializedCharDetails = fonts.SerializedCharDetails;

var enable_typing: *const fn () void = undefined;
pub const TextCallback = fn (text: []u8) void;
var update_text_content: *const TextCallback = undefined;
var disable_typing: *const fn () void = undefined;
pub fn connectTyping(
    enable: *const fn () void,
    disable: *const fn () void,
    update: *const fn ([]u8) void,
    getCharData: *const fn (u32, u8) fonts.SerializedCharDetails,
    getKerning: *const fn (u8, u8) f32,
) void {
    enable_typing = enable;
    disable_typing = disable;
    update_text_content = update;
    fonts.getCharData = getCharData;
    fonts.getKerning = getKerning;
}

pub const @"meta(zigar)" = struct {
    pub fn isArgumentString(comptime FT: type, comptime arg_index: usize) bool {
        _ = arg_index;
        return switch (FT) {
            TextCallback => true,
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
const NO_SELECTION = 0;
const MIN_NEW_CONTROL_POINT_DISTANCE = 10.0; // Minimum distance to consider a new control point

const ActionType = enum {
    Move,
    None,
    Transform,
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
    hovered_asset_id: u32,
    selected_asset_id: u32,
    action: ActionType,
    tool: Tool,
    last_pointer_coords: types.Point,
};

var state = State{
    .width = 0,
    .height = 0,
    .assets = undefined,
    .hovered_asset_id = NO_SELECTION,
    .selected_asset_id = NO_SELECTION,
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
                const bounds = shape.getBoundsWithPadding(1 / shared.render_scale, false);
                const new_size = texture_size.get_sdf_size(bounds);

                if (new_size.w > shape.sdf_size.w or new_size.h > shape.sdf_size.h) {
                    shape.outdated_sdf = true;
                }
            },
            .text => {},
        }
    }
}

var next_asset_id: u32 = ASSET_ID_MIN;
fn generateId() u32 {
    const id = next_asset_id;
    next_asset_id +%= 1;
    // TODO: once hits PackedId.ASSET_ID_MAX we should re-indentify all assets
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

pub fn addText(
    id_or_zero: u32,
    content: []const u8,
    bounds: ?[4]types.PointUV,
    start: types.Point,
    max_width: f32,
    font_size: f32,
) !u32 {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const text = texts.Text.new(
        id,
        content,
        bounds,
        start,
        max_width,
        font_size,
    );
    try state.assets.put(id, Asset{ .text = text });
    try checkAssetsUpdate(true);
    return id;
}

pub fn removeAsset() !void {
    _ = state.assets.orderedRemove(state.selected_asset_id);
    try updateSelectedAsset(NO_SELECTION);
    try checkAssetsUpdate(true);
}

pub fn onUpdatePick(id: u32) void {
    if (state.action != .Transform) {
        state.hovered_asset_id = id;
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
                    .text = text.serialize(),
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
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => |*img| return img,
        .shape => return null,
        .text => return null,
    }
}

fn getSelectedShape() ?*shapes.Shape {
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
        .text => return null,
    }
}

fn getSelectedText() ?*texts.Text {
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => return null,
        .text => |*text| return text,
    }
}

fn updateSelectedAsset(id: u32) !void {
    try commitChanges();

    if (id >= PackedId.MIN_PACKED_ID) {
        const point_id = PackedId.decode(id);
        shapes.selected_point_id = point_id;
        state.selected_asset_id = point_id.shape;
    } else {
        state.selected_asset_id = id;
    }
    on_asset_select_cb(id);
}

// pub const @"meta(zigar)" = struct {
//     pub fn isFieldString(comptime T: type, comptime field_name: []const u8) bool {
//         _ = field_name;
//         return switch (T) {
//             texts.Text => true,
//             else => false,
//         };
//     }
// };

pub fn updateTextContent(new_content: []const u8) void {
    const option_text = getSelectedText();
    if (option_text) |text| {
        text.updateContent(new_content);
    } else {
        @panic("updateTextContent called but no text asset selected");
    }
}

pub fn onPointerDown(x: f32, y: f32) !void {
    if (state.tool == .Text) {
        const id = generateId();
        _ = try addText(
            id,
            "",
            null,
            types.Point{ .x = x, .y = y },
            200.0,
            72.0,
        );
        state.selected_asset_id = id;
        enable_typing();
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
                .filter = .{ .gaussianBlur = .{ .x = 3, .y = 3 } },
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
            try updateSelectedAsset(id);
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
            // sould not be accessible on mobile, that's why selection happens with pointer down
            if (state.hovered_asset_id != NO_SELECTION) {
                try updateSelectedAsset(state.hovered_asset_id);
            }
        }

        if (state.selected_asset_id == NO_SELECTION) {
            // No active asset, do nothing
        } else if (TransformUI.isTransformUi(state.hovered_asset_id)) {
            state.action = .Transform;
        } else if (state.selected_asset_id >= ASSET_ID_MIN and state.selected_asset_id == state.hovered_asset_id) {
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
        shapes.selected_point_id = null;
    }
}

pub fn onPointerMove(x: f32, y: f32) void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            shape.updatePointPreview(types.Point{ .x = x, .y = y });
        }
        return;
    }

    if (state.tool == Tool.EditShape) {
        if (shapes.selected_point_id) |selected_point_id| {
            if (getSelectedShape()) |shape| {
                const matrix = Matrix3x3.getMatrixFromRectangle(shape.bounds);
                const pointer = matrix.inverse().get(types.Point{ .x = x, .y = y });

                const path = shape.paths.items[selected_point_id.path];
                const points = path.points.items;
                const i = selected_point_id.point;

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

    const asset = state.assets.getPtr(state.selected_asset_id) orelse return;
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
                state.hovered_asset_id,
                bounds,
                types.Point{ .x = x, .y = y },
            );
            switch (asset.*) {
                .img => {},
                .shape => |*shape| {
                    shape.should_update_sdf = true;
                },
                .text => {},
            }
        },
        .None => {},
    }
}

pub fn onPointerLeave() !void {
    state.action = .None;
    state.hovered_asset_id = 0;
    try checkAssetsUpdate(true);
}

pub fn commitChanges() !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            shape.update_preview_point(null);
        }

        shapes.resetState();
    }
}
// TODO: extract to another file and simplify(extract common code)
// https://github.com/users/mateuszJS/projects/1/views/1?pane=issue&itemId=123400787&issue=mateuszJS%7Cmagic-render%7C122
fn drawBorder(allocator: std.mem.Allocator) !void {
    var triangle_vertex_data = std.ArrayList(Triangle.DrawInstance).init(allocator);
    var ui_vertex_data = std.ArrayList(UI.DrawVertex).init(allocator);

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id != state.selected_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
                .text => |text| text.bounds,
            };

            for (points, 0..) |point, i| {
                const next_point = if (i == 3) points[0] else points[i + 1];
                var buffer: [2]Triangle.DrawInstance = undefined;

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
    if (state.assets.get(state.selected_asset_id)) |asset| {
        const points = switch (asset) {
            .img => |img| img.points,
            .shape => |shape| shape.bounds,
            .text => |text| text.bounds,
        };

        for (points, 0..) |point, i| {
            const next_point = if (i == 3) points[0] else points[i + 1];
            var buffer: [2]Triangle.DrawInstance = undefined;

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

        var triangle_buffer: [TransformUI.RENDER_TRIANGLE_INSTANCES]Triangle.DrawInstance = undefined;

        try TransformUI.getDrawVertexData(
            &triangle_buffer,
            &ui_vertex_data,
            points,
            state.hovered_asset_id,
        );

        try triangle_vertex_data.appendSlice(&triangle_buffer);
    }

    if (triangle_vertex_data.items.len > 0) {
        web_gpu_programs.draw_triangle(triangle_vertex_data.items);
    }

    try UI.draw(ui_vertex_data.items, web_gpu_programs.draw_shape);
}

fn drawProjectBackground() void {
    var buffer: [2]Triangle.DrawInstance = undefined;
    rects.getDrawVertexData(
        &buffer,
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
    var buffer: [2 * 4]Triangle.DrawInstance = undefined;

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

pub fn calculateShapesSDF() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

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

                const option_points = try shape.getNewSdfPoint(allocator);
                if (option_points) |points| {
                    const bounds = shape.getBoundsWithPadding(1 / shared.render_scale, false);
                    shape.sdf_size = texture_size.get_sdf_size(bounds);

                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
                    // * shared.render_scale to revert to logical scale, without impact of camera/zoom

                    shape.sdf_scale = shape.sdf_size.w / init_width;

                    for (points) |*point| {
                        point.x *= shape.sdf_scale;
                        point.y *= shape.sdf_scale;
                    }

                    if (shape.sdf_size.w > consts.MIN_TEXTURE_SIZE and shape.sdf_size.h > consts.MIN_TEXTURE_SIZE) {
                        web_gpu_programs.compute_shape(
                            points,
                            @floor(shape.sdf_size.w),
                            @floor(shape.sdf_size.h),
                            shape.sdf_texture_id,
                        );

                        shape.outdated_cache = true;
                    }
                }

                shape.outdated_sdf = false;
                shape.should_update_sdf = false;
            },
            .text => {},
        }
    }

    var iter = fonts.fonts.iterator();
    while (iter.next()) |f| {
        var font = f.value_ptr.*;
        var char_iter = font.chars.iterator();
        while (char_iter.next()) |details| {
            var d = details.value_ptr;
            if (!d.outdated_sdf) continue;

            const w = 100.0 * d.width;
            const h = 100.0 * d.height;

            // const bounds = [4]types.PointUV{
            //     .{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
            //     .{ .x = w, .y = 0.0, .u = 1.0, .v = 0.0 },
            //     .{ .x = w, .y = h, .u = 1.0, .v = 1.0 },
            //     .{ .x = 0.0, .y = h, .u = 0.0, .v = 1.0 },
            // };
            // const sdf_size = texture_size.get_sdf_size(bounds);

            // const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
            // * shared.render_scale to revert to logical scale, without impact of camera/zoom

            // shape.sdf_scale = shape.sdf_size.w / init_width;
            const ps = try std.heap.page_allocator.dupe(types.Point, d.points);
            for (ps) |*point| {
                point.x = point.x * 100.0;
                point.y = point.y * 100.0;
            }

            // if (shape.sdf_size.w > consts.MIN_TEXTURE_SIZE and shape.sdf_size.h > consts.MIN_TEXTURE_SIZE) {
            web_gpu_programs.compute_shape(
                ps,
                @floor(w),
                @floor(h),
                d.sdf_texture_id,
            );

            d.outdated_sdf = false;
            // }
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

                    const bounds = shape.getBoundsWithPadding(
                        1 / shared.render_scale,
                        true,
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

var last_start_update: u32 = 0;
var last_end_update: u32 = 0;

pub fn setCaretPosition(start: u32, end: u32) void {
    if (start != end) { // selection
        if (last_end_update != end) { // the end has changed, so move caret there
            texts.caret_position = end;
            texts.selection_end_position = start;
        } else { // otherwise means start has changed, so move caret there
            texts.caret_position = start;
            texts.selection_end_position = end;
        }
    } else {
        texts.caret_position = start;
        texts.selection_end_position = end;
    }
    texts.last_caret_update = time_u32;

    last_start_update = start;
    last_end_update = end;
}

pub fn drawCaret(position: types.Point, height: f32) void {
    const blink = (time_u32 / 700) % 2 == 0;
    const newly_updated = time_u32 - texts.last_caret_update < 1000;

    if (blink or newly_updated) {
        var buffer: [2]Triangle.DrawInstance = undefined;
        const width = 3.0 * shared.render_scale;
        lines.getDrawVertexData(&buffer, position, types.Point{
            .x = position.x,
            .y = position.y + height,
        }, width, .{ 255, 255, 255, 255 }, width / 2);
        web_gpu_programs.draw_triangle(&buffer);
    }
}

fn drawTextSelection(start: types.Point, width: f32, height: f32) void {
    var buffer: [2]Triangle.DrawInstance = undefined;
    rects.getDrawVertexData(
        &buffer,
        start.x,
        start.y,
        width,
        height,
        0.0,
        .{ 0, 50, 50, 50 },
    );
    web_gpu_programs.draw_triangle(&buffer);
}

const ENTER_CHAR_CODE = 10;
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
                if (shape.cache_texture_id) |cache_texture_id| {
                    web_gpu_programs.draw_texture(
                        &shape.getDrawBounds(true),
                        cache_texture_id,
                    );
                } else {
                    for (shape.props.sdf_effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &shape.getDrawBounds(true),
                            shape.getDrawUniform(effect),
                            shape.sdf_texture_id,
                        );
                    }
                }
            },
            .text => |*text| {
                const is_typing_ui = state.tool == .Text and state.selected_asset_id == text.id;
                const lh = text.font_size * text.line_height;
                var new_content = std.ArrayList(u8).init(allocator);
                var max_width: f32 = 0.0;

                const origin = types.Point{ // start of the very first char(bottom left corner of the char)
                    .x = text.start.x,
                    .y = text.start.y - lh,
                };
                var next_pos = origin;
                var start_selection: ?types.Point = null; // used only to capture caret position to draw selection

                for (text.content, 0..) |c, i| {
                    if (is_typing_ui and texts.caret_position == i) {
                        drawCaret(next_pos, lh);
                    }

                    const pos = next_pos;

                    // Draw selection if it's just the end of selection
                    if (is_typing_ui and (texts.caret_position == i or texts.selection_end_position == i)) {
                        if (start_selection) |start| {
                            const started_this_line = Utils.equalF32(start.y, next_pos.y);
                            const begin_selection = types.Point{
                                .x = if (started_this_line) start.x else origin.x,
                                .y = next_pos.y,
                            };
                            drawTextSelection(
                                begin_selection,
                                next_pos.x - begin_selection.x,
                                lh,
                            );
                            start_selection = null;
                        } else {
                            start_selection = next_pos;
                        }
                    }

                    if (c == ENTER_CHAR_CODE) {
                        next_pos = types.Point{
                            .x = origin.x,
                            .y = next_pos.y - lh,
                        };
                    } else if (c == ' ') {
                        next_pos.x += text.font_size * 0.3;
                    } else {
                        const uniform = sdf.DrawUniform{
                            .solid = .{
                                .dist_start = std.math.inf(f32),
                                .dist_end = 0,
                                .color = .{ 0.9, 0.9, 0, 1 },
                            },
                        };
                        const char_details = try fonts.get(0, c);
                        const char_width = (char_details.x + char_details.width) * text.font_size;

                        // ensure is within text.max_width
                        if ((next_pos.x + char_width) - origin.x > text.max_width) {
                            next_pos = types.Point{
                                .x = origin.x,
                                .y = next_pos.y - lh,
                            };
                            if (i != text.content.len - 1) { // do not add soft break if it's the last char
                                // add word joiner character before line break so that when user copies the text, they get the same line breaks
                                try new_content.appendSlice("\u{2060}");
                                try new_content.append(ENTER_CHAR_CODE);
                            }
                        }

                        const bounds = text.getDrawBounds(char_details, next_pos);
                        // for (shape.props.sdf_effects.items) |effect| {
                        web_gpu_programs.draw_shape(
                            &bounds,
                            uniform,
                            char_details.sdf_texture_id,
                        );
                        // }

                        next_pos.x += char_width;

                        max_width = @max(max_width, next_pos.x - origin.x);
                    }

                    try new_content.append(c);

                    if (!Utils.equalF32(pos.y, next_pos.y)) {
                        const is_selection = texts.caret_position != texts.selection_end_position;
                        if (is_selection) {
                            if (start_selection) |start| {
                                const started_this_line = Utils.equalF32(start.y, pos.y);
                                const started_previous_line = start.y > pos.y - std.math.floatEps(f32);
                                if (started_this_line) {
                                    drawTextSelection(
                                        start,
                                        pos.x - start.x,
                                        lh,
                                    );
                                } else if (started_previous_line) {
                                    const begin_selection = types.Point{
                                        .x = origin.x,
                                        .y = pos.y,
                                    };
                                    drawTextSelection(
                                        begin_selection,
                                        pos.x - begin_selection.x,
                                        lh,
                                    );
                                }
                            }
                        }
                    }
                }

                // draw selection & caret if those appear at the very end of the text! (includes when there is no text)
                if (is_typing_ui) {
                    if (texts.caret_position == text.content.len) {
                        drawCaret(next_pos, lh);
                    }

                    if (texts.caret_position == text.content.len or texts.selection_end_position == text.content.len) {
                        if (start_selection) |start| {
                            const begin_selection = types.Point{
                                .x = if (Utils.equalF32(start.y, next_pos.y)) start.x else origin.x,
                                .y = next_pos.y,
                            };

                            drawTextSelection(
                                begin_selection,
                                next_pos.x - begin_selection.x,
                                lh,
                            );
                        }
                    }
                }

                text.bounds = [_]types.PointUV{
                    .{ .x = text.start.x, .y = text.start.y, .u = 0.0, .v = 1.0 },
                    .{ .x = text.start.x + max_width, .y = text.start.y, .u = 1.0, .v = 1.0 },
                    .{ .x = text.start.x + max_width, .y = next_pos.y, .u = 1.0, .v = 0.0 },
                    .{ .x = text.start.x, .y = next_pos.y, .u = 0.0, .v = 0.0 },
                };

                if (text.id == state.selected_asset_id and !std.meta.eql(text.content, new_content.items)) {
                    update_text_content(new_content.items);
                }
            },
        }
    }

    drawProjectBoundary(); // TODO: once we support strokes for Triangles, we should use it here wit transparent fill

    if (state.tool == .None or state.tool == .Text) {
        try drawBorder(allocator);
    }

    if (state.tool == Tool.DrawShape or state.tool == Tool.EditShape) {
        const hover_point_id = PackedId.decode(state.hovered_asset_id);
        const select_point_id = shapes.selected_point_id;
        _ = select_point_id; // autofix

        if (getSelectedShape()) |shape| {
            web_gpu_programs.draw_shape(
                &shape.getDrawBounds(false),
                shape.getSkeletonUniform(),
                shape.sdf_texture_id,
            );

            const hover_id = if (shape.id == hover_point_id.shape) hover_point_id else null;
            const vertex_data = try shape.getSkeletonDrawVertexData(
                allocator,
                hover_id,
                state.tool == Tool.DrawShape,
            );
            web_gpu_programs.draw_triangle(vertex_data);
        }
    }

    // testing:

    // const points = [_]types.Point{
    //     types.Point{ .x = 100.0, .y = 70.0 }, //
    //     types.Point{ .x = 300.0, .y = 100.0 }, //
    //     types.Point{ .x = 300.0, .y = 250.0 }, //
    //     types.Point{ .x = 100.0, .y = 150.0 }, //
    // };
    // const p0_v = Triangle.get_round_corner_vector(0, points, 10.0);
    // const p1_v = Triangle.get_round_corner_vector(1, points, 20.0);
    // const p2_v = Triangle.get_round_corner_vector(2, points, 80.0);
    // const p3_v = Triangle.get_round_corner_vector(3, points, 20.0);

    // const color = [_]u8{ 0, 255, 255, 255 };

    // var shape_vertex_data: [2]Triangle.DrawInstance = undefined;

    // Triangle.get_draw_vertex_data(shape_vertex_data[0..1], p0_v, p1_v, p2_v, color);
    // Triangle.get_draw_vertex_data(shape_vertex_data[1..2], p0_v, p2_v, p3_v, color);

    // web_gpu_programs.draw_triangle(&shape_vertex_data);

    // const msdf_vertex_data = Msdf.get_draw_vertex_data(
    //     Msdf.IconId.rotate,
    //     10.0,
    //     10.0,
    //     100.0,
    //     [_]u8{ 255, 0, 0, 255 },
    // );
    // web_gpu_programs.draw_msdf(&msdf_vertex_data, 0);
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
            .text => {},
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
        if (state.assets.get(state.selected_asset_id)) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
                .text => |text| text.bounds,
            };
            var vertex_buffer: [TransformUI.PICK_TRIANGLE_INSTANCES]Triangle.PickInstance = undefined;
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
                    text.content,
                    text.bounds,
                    text.start,
                    text.max_width,
                    text.font_size,
                );
            },
        }
    }

    if (!state.assets.contains(state.selected_asset_id)) {
        try updateSelectedAsset(NO_SELECTION);
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
    state.selected_asset_id = 0;
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
}

var time: f32 = 0.0;
var time_u32: u32 = 0;
var ticks: u32 = 0; // it's like a time, but always increases by 1, used for performance optimizations
pub fn tick(now: f32) void {
    ticks +%= 1;
    time = now;
    time_u32 = @intFromFloat(time);
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
