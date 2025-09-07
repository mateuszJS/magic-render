const std = @import("std");
const types = @import("types.zig");
const images = @import("images.zig");
const lines = @import("lines.zig");
const Triangle = @import("triangle.zig");
const TransformUI = @import("transform_ui.zig");
const zigar = @import("zigar");
const Msdf = @import("msdf.zig");
const shapes = @import("./shapes/shapes.zig");
const squares = @import("squares.zig");
const bounding_box = @import("shapes/bounding_box.zig");
const shared = @import("shared.zig");
const texture_size = @import("texture_size.zig");
const Utils = @import("utils.zig");
const PackedId = @import("shapes/packed_id.zig");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const PathUtils = @import("shapes/path_utils.zig");
const consts = @import("consts.zig");

const FillType = enum(u8) {
    Solid,
    LinearGradient,
    RadialGradient,
};

const WebGpuPrograms = struct {
    draw_texture: *const fn (images.DrawVertex, u32) void,
    draw_triangle: *const fn ([]const Triangle.DrawInstance) void,
    compute_shape: *const fn ([]const types.Point, f32, f32, u32) void,
    draw_blur: *const fn (u32, u32, u32, u32, f32, f32) void,
    draw_shape: *const fn ([]const types.PointUV, shapes.Uniform, u32) void,
    draw_msdf: *const fn ([]const Msdf.DrawInstance, u32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
    pick_shape: *const fn ([]const images.PickVertex, f32, u32) void,
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

    // shapes.update_texture_cache = update_texture_cache;
}

fn update_texture_cache(texture_id: u32, box: bounding_box.BoundingBox, width: f32, height: f32) void {
    start_cache(texture_id, box, width, height);
    // web_gpu_programs.compute_shape(vertex_data.curves);
    end_cache();
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
};

const Asset = union(enum) {
    img: images.Image,
    shape: shapes.Shape,
};

const AssetSerialized = union(enum) {
    img: images.Serialized,
    shape: shapes.Serialized,
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

pub fn initState(width: f32, height: f32, texture_max_size: f32, max_buffer_size: f32) void {
    shared.texture_max_size = texture_max_size;
    shared.max_buffer_size = max_buffer_size;
    state.width = width;
    state.height = height;
    state.assets = std.AutoArrayHashMap(u32, Asset).init(std.heap.page_allocator);
    // shapes.maxTextureSize = texture_max_size;
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
                    .shape = try shape.serialize(),
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
    }
}

fn getSelectedShape() ?*shapes.Shape {
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
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

pub fn onPointerDown(x: f32, y: f32) !void {
    if (state.tool == Tool.DrawShape) {
        if (state.selected_asset_id == NO_SELECTION) {
            const props = shapes.SerializedProps{
                .fill = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
                .stroke = .{ .solid = .{ 0.0, 0.0, 0.0, 1.0 } },
                .stroke_width = 1.0,
                .filter = .{ .gaussianBlur = .{ .x = 30, .y = 1 } },
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

        return;
    }

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
fn getBorder(allocator: std.mem.Allocator) struct { []Triangle.DrawInstance, []Msdf.DrawInstance } {
    var triangle_vertex_data = std.ArrayList(Triangle.DrawInstance).init(allocator);
    var msdf_vertex_data = std.ArrayList(Msdf.DrawInstance).init(allocator);

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id != state.selected_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
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

                triangle_vertex_data.appendSlice(&buffer) catch unreachable;
            }
        }
    }

    const green = [_]u8{ 0, 255, 0, 255 };
    if (state.assets.get(state.selected_asset_id)) |asset| {
        const points = switch (asset) {
            .img => |img| img.points,
            .shape => |shape| shape.bounds,
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

            triangle_vertex_data.appendSlice(&buffer) catch unreachable;
        }

        var triangle_buffer: [TransformUI.RENDER_TRIANGLE_INSTANCES]Triangle.DrawInstance = undefined;
        var msdf_buffer: [2]Msdf.DrawInstance = undefined;

        TransformUI.getDrawVertexData(
            &triangle_buffer,
            &msdf_buffer,
            points,
            state.hovered_asset_id,
        );

        triangle_vertex_data.appendSlice(&triangle_buffer) catch unreachable;
        msdf_vertex_data.appendSlice(&msdf_buffer) catch unreachable;
    }

    return .{
        triangle_vertex_data.items,
        msdf_vertex_data.items,
    };
}

fn drawProjectBackground() void {
    var buffer: [2]Triangle.DrawInstance = undefined;
    squares.getDrawVertexData(
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
                if (!shape.outdated_sdf) {
                    continue;
                }

                const option_points = try shape.getNewSdfPoint(allocator);
                if (option_points) |points| {
                    // TODO: rethink if SDF really needs blur to be included in the padding
                    const bounds = shape.getBoundsWithPadding(1 / shared.render_scale, false);
                    shape.sdf_size = texture_size.get_sdf_size(bounds);
                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale; // * shared.render_scale to revert to logical scale, nothing screen/camera/zoom related
                    shape.sdf_scale = shape.sdf_size.w / init_width;

                    for (points) |*point| {
                        point.x *= shape.sdf_scale;
                        point.y *= shape.sdf_scale;
                    }

                    if (shape.sdf_size.w > 1.001 and shape.sdf_size.h > 1.001) {
                        web_gpu_programs.compute_shape(
                            points,
                            @floor(shape.sdf_size.w),
                            @floor(shape.sdf_size.h),
                            shape.sdf_texture_id,
                        );

                        shape.outdated_cache = true;
                    }
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

                    const bounds = shape.getBoundsWithPadding(
                        1 / shared.render_scale,
                        true,
                    );
                    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale; // * shared.render_scale to revert to logical scale, nothing screen/camera/zoom related
                    const initial_size = texture_size.get_size(bounds);
                    const init_cache_scale = initial_size.w / init_width;

                    // Cost control: scale down texture if blur cost is too high
                    const initial_sigma = types.Point{
                        .x = filter.gaussianBlur.x * init_cache_scale,
                        .y = filter.gaussianBlur.y * init_cache_scale,
                    };
                    const size, const sigma = texture_size.get_safe_blur_dims(
                        initial_size,
                        initial_sigma,
                    );

                    if (size.w < 1.001 or size.h < 1.001) continue;
                    // just to make sure device.createTexture won't round number down to 0

                    shape.cache_scale = size.w / init_width;

                    const extra_padding = shape.getFilterMargin();
                    const scaled_extra_padding = types.Point{
                        .x = extra_padding.x * shape.cache_scale,
                        .y = extra_padding.y * shape.cache_scale,
                    };
                    const bb = bounding_box.BoundingBox{
                        .min_x = -scaled_extra_padding.x,
                        .min_y = -scaled_extra_padding.y,
                        .max_x = size.w + scaled_extra_padding.x,
                        .max_y = size.h + scaled_extra_padding.y,
                    };

                    start_cache(cache_texture_id, bb, size.w, size.h);

                    const vertex_bounds = [_]types.PointUV{
                        // first triangle
                        .{ .x = 0, .y = 0, .u = 0, .v = 0 },
                        .{ .x = 0, .y = size.h, .u = 0, .v = 1 },
                        .{ .x = size.w, .y = size.h, .u = 1, .v = 1 },
                        // second triangle
                        .{ .x = size.w, .y = size.h, .u = 1, .v = 1 },
                        .{ .x = size.w, .y = 0, .u = 1, .v = 0 },
                        .{ .x = 0, .y = 0, .u = 0, .v = 0 },
                    };

                    web_gpu_programs.draw_shape(
                        &vertex_bounds,
                        shape.getUniform(),
                        shape.sdf_texture_id,
                    );

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
                    const filter_size_per_pass_x = @max(1, @ceil(factor * sigma_per_pass_x));
                    const filter_size_per_pass_y = @max(1, @ceil(factor * sigma_per_pass_y));

                    web_gpu_programs.draw_blur(
                        cache_texture_id,
                        @as(u32, @intFromFloat(iterations)),
                        @as(u32, @intFromFloat(filter_size_per_pass_x)) | 1, // Ensure odd
                        @as(u32, @intFromFloat(filter_size_per_pass_y)) | 1,
                        sigma_per_pass_x,
                        sigma_per_pass_y,
                    );

                    shape.outdated_cache = false;
                }
            },
        }
    }
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
                var vertex_data: images.DrawVertex = undefined;
                img.getRenderVertexData(&vertex_data);
                web_gpu_programs.draw_texture(vertex_data, img.texture_id);
            },
            .shape => |*shape| {
                if (shape.cache_texture_id) |cache_texture_id| {
                    web_gpu_programs.draw_texture(
                        shape.getDrawBounds(true),
                        cache_texture_id,
                    );
                } else {
                    web_gpu_programs.draw_shape(
                        &shape.getDrawBounds(true),
                        shape.getUniform(),
                        shape.sdf_texture_id,
                    );
                }
            },
        }
    }

    drawProjectBoundary(); // TODO: once we support strokes for Triangles, we should use it here wit transparent fill

    if (state.tool == Tool.None) {
        const triangle_buffer, const msdf_buffer = getBorder(allocator);
        if (triangle_buffer.len > 0) {
            web_gpu_programs.draw_triangle(triangle_buffer);
        }
        if (msdf_buffer.len > 0) {
            web_gpu_programs.draw_msdf(msdf_buffer, 0);
        }
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
                web_gpu_programs.pick_shape(
                    &shape.getPickBounds(),
                    shape.getStrokeWidth(),
                    shape.sdf_texture_id,
                );
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
        if (state.assets.get(state.selected_asset_id)) |asset| {
            const points = switch (asset) {
                .img => |img| img.points,
                .shape => |shape| shape.bounds,
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
        }
    }

    if (!state.assets.contains(state.selected_asset_id)) {
        try updateSelectedAsset(NO_SELECTION);
    }
    on_asset_update_cb = original_on_asset_update_cb;
    try checkAssetsUpdate(with_snapshot);
}

pub fn destroyState() void {
    state.assets.clearAndFree();
    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = &.{};
    Msdf.deinitIcons();
    state.selected_asset_id = 0;
    next_asset_id = ASSET_ID_MIN;
    web_gpu_programs = undefined;
    on_asset_update_cb = undefined;
    // state itself is not destoyed as it will be reinitalized before usage
    // and has no reference to memory to free
}

pub fn importIcons(data: []const f32) void {
    Msdf.initIcons(data);
}

pub fn setTool(tool: Tool) !void {
    try commitChanges();
    state.tool = tool;
}

pub fn stopDrawingShape() void {
    state.selected_asset_id = NO_SELECTION;
}

test "reset_assets does not call the real update callback" {
    // Setup initial state
    initState(100, 100);
    // Ensure state is cleaned up after the test
    defer destroyState();

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
