const std = @import("std");
const types = @import("./types.zig");
const images = @import("./images.zig");
const Line = @import("line.zig");
const Triangle = @import("triangle.zig");
const TransformUI = @import("./transform_ui.zig");
const zigar = @import("zigar");
const Msdf = @import("./msdf.zig");
const shapes = @import("./shapes/shapes.zig");
const squares = @import("squares.zig");
const bounding_box = @import("shapes/bounding_box.zig");
const shared = @import("./shared.zig");

const WebGpuPrograms = struct {
    draw_texture: *const fn (images.DrawVertex, u32) void,
    draw_triangle: *const fn ([]const Triangle.DrawInstance) void,
    compute_shape: *const fn ([]const types.Point, f32, f32) void,
    draw_shape: *const fn ([]const types.PointUV, shapes.Uniform) void,
    draw_msdf: *const fn ([]const Msdf.DrawInstance, u32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
    pick_shape: *const fn ([]const images.PickVertex, shapes.Uniform) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;

pub fn connectWebGpuPrograms(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

var on_asset_update_cb: ?*const fn ([]const AssetSerialized) void = undefined;
pub fn connectOnAssetUpdateCallback(cb: *const fn ([]const AssetSerialized) void) void {
    on_asset_update_cb = cb;
}

var on_asset_select_cb: *const fn (u32) void = undefined;
pub fn connectOnAssetSelectionCallback(cb: *const fn (u32) void) void {
    on_asset_select_cb = cb;
}

var create_cache_texture_callback: *const fn () u32 = undefined;
var start_cache_callback: *const fn (u32, bounding_box.BoundingBox, f32, f32) void = undefined;
var end_cache_callback: *const fn () void = undefined;

pub fn connectCacheCallbacks(
    create_cache_texture: *const fn () u32,
    start_cache: *const fn (u32, bounding_box.BoundingBox, f32, f32) void,
    end_cache: *const fn () void,
) void {
    create_cache_texture_callback = create_cache_texture;
    start_cache_callback = start_cache;
    end_cache_callback = end_cache;

    shapes.update_texture_cache = update_texture_cache;
}

fn update_texture_cache(texture_id: u32, box: bounding_box.BoundingBox, vertex_data: shapes.DrawVertexOutput, width: f32, height: f32) void {
    _ = vertex_data; // autofix
    start_cache_callback(texture_id, box, width, height);
    // web_gpu_programs.compute_shape(vertex_data.curves);
    end_cache_callback();
}

pub const ASSET_ID_TRESHOLD: u32 = 1000;
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

    active_path_index: ?usize = null,
    preview_point: ?types.Point = null,
    is_handle_preview: bool = false,
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

pub fn initState(allocator: std.mem.Allocator, width: f32, height: f32, texture_max_size: f32) void {
    _ = allocator; // autofix
    state.width = width;
    state.height = height;
    state.assets = std.AutoArrayHashMap(u32, Asset).init(std.heap.page_allocator);
    shapes.maxTextureSize = texture_max_size;
}

pub fn updateRenderScale(scale: f32) !void {
    shared.render_scale = scale;

    var iterator = state.assets.iterator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = allocator; // autofix

    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                if (shape.cache.valid) {
                    // if it's valid, then lets update, if it's invalid, then is gonna be updated anyway(with correct fresh data)
                    // if (shape.updateTextureSize()) {
                    //     std.debug.print("texture size has changed, updating shape cache\n", .{});
                    //     try shape.drawTextureCache(allocator);
                    // }
                }
            },
        }
    }
}

var next_asset_id: u32 = ASSET_ID_TRESHOLD;
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
    props: shapes.ShapeProps,
    cache: shapes.TextureCache,
) !u32 {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const shape = try shapes.Shape.new(
        id,
        paths,
        bounds,
        props,
        cache,
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
    std.debug.print("updateSelectedAsset called with id: {}\n", .{id});
    state.selected_asset_id = id;
    state.active_path_index = null;
    on_asset_select_cb(id);
}

pub fn onPointerDown(_allocator: std.mem.Allocator, x: f32, y: f32) !void {
    _ = _allocator; // autofix
    if (state.tool == Tool.DrawShape) {
        const preview_point = types.Point{ .x = x, .y = y };
        state.preview_point = preview_point;
        if (state.selected_asset_id == NO_SELECTION) {
            const id = try addShape(
                0,
                &.{},
                null,
                shapes.ShapeProps{},
                shapes.TextureCache{ .id = create_cache_texture_callback() },
            );
            try updateSelectedAsset(id);
        }

        if (getSelectedShape()) |shape| {
            state.active_path_index = try shape.addPointStart(
                std.heap.page_allocator,
                preview_point,
                state.active_path_index,
            );
            state.is_handle_preview = true;
            return;
        } else {
            @panic("Selected shape asset should be present at this point");
        }

        return;
    }

    if (state.selected_asset_id == NO_SELECTION) {
        // No active asset, do nothing
    } else if (TransformUI.isTransformUi(state.hovered_asset_id)) {
        state.action = .Transform;
    } else if (state.selected_asset_id >= ASSET_ID_TRESHOLD and state.selected_asset_id == state.hovered_asset_id) {
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
        if (state.active_path_index) |active_path_index| {
            const shape = getSelectedShape() orelse @panic("Selected shape asset should be present when active_path_index is not null");
            if (shape.paths.items[active_path_index].closed) {
                std.debug.print("SHAPE CLOSED, {d}\n", .{active_path_index});
                state.active_path_index = null;
            }
            try checkAssetsUpdate(true);
        }
        state.is_handle_preview = false;
    }
}

pub fn onPointerMove(x: f32, y: f32) !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            const preview_point = types.Point{ .x = x, .y = y };
            state.preview_point = preview_point;

            if (state.active_path_index) |active_path_index| {
                if (state.is_handle_preview) {
                    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                    defer arena.deinit();
                    const allocator = arena.allocator();

                    try shape.updateLastHandle(
                        allocator,
                        shapes.Preview{ .index = active_path_index, .point = preview_point },
                    );
                }
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
            TransformUI.transformPoints(state.hovered_asset_id, bounds, x, y);
        },
        .None => {},
    }
}

pub fn onPointerLeave() !void {
    state.action = .None;
    state.hovered_asset_id = 0;
    try checkAssetsUpdate(true);
}

fn updateShapeCache(shape: *shapes.Shape) !void {
    _ = shape; // autofix
    // if (shape.cache.valid) {
    //     return; // no need to update
    // }

    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // try shape.drawTextureCache(allocator);
}

pub fn commitChanges() !void {
    if (state.tool == Tool.DrawShape) {
        if (getSelectedShape()) |shape| {
            try updateShapeCache(shape);
        }

        state.preview_point = null;
        state.active_path_index = null;
        state.is_handle_preview = false;
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

                Line.getDrawVertexData(
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

            Line.getDrawVertexData(
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

        Line.getDrawVertexData(
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
                var preview: ?shapes.Preview = null;
                if (state.active_path_index) |active_path_index| {
                    if (state.preview_point) |preview_point| {
                        preview = shapes.Preview{ .index = active_path_index, .point = preview_point };
                    }
                }

                const option_vertex_data = try shape.getDrawVertexData(
                    allocator,
                    preview,
                );

                if (option_vertex_data) |vertex_data| {
                    const bounds = shape.getBoundsWithPadding();
                    web_gpu_programs.compute_shape(
                        vertex_data.curves,
                        bounds[0].distance(bounds[1]),
                        bounds[0].distance(bounds[3]),
                        // @max(1.0, bounds[0].distance(bounds[1])),
                        // @max(1.0, bounds[0].distance(bounds[3])),
                    );
                }
            },
        }
    }
}

const point_size: f32 = @floatFromInt(@sizeOf(types.Point)); // 8 bytes
const triangle_size: f32 = @floatFromInt(@sizeOf(Triangle.DrawInstance)); // 64 bytes
const asset_size: f32 = @floatFromInt(@sizeOf(images.DrawVertex)); // 96 bytes

pub fn renderDraw() !void {
    // Add some padding for allocator overhead (usually ~16-32 bytes per allocation)
    // const allocator_overhead = 64;

    // const estimated_memory =
    //     triangle_size * 2.0 + // project background
    //     triangle_size * 4.0 + // project border
    //     asset_size * @as(f32, @floatFromInt(state.assets.count())) + // assets
    //     point_size * 100.0 + allocator_overhead; // shapes

    // const safety_margin = 1.2; // 20% extra

    // // Are you building for WebAssembly? In this case, std.heap.wasm_allocator is likely the right
    // // choice for your main allocator as it uses WebAssembly's memory instructions.

    // const total_size = @as(usize, @intFromFloat(estimated_memory * safety_margin));

    // var buffer: [total_size]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
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
                var preview: ?shapes.Preview = null;
                if (state.active_path_index) |active_path_index| {
                    if (state.preview_point) |preview_point| {
                        preview = shapes.Preview{ .index = active_path_index, .point = preview_point };
                    }
                }

                const option_vertex_data = try shape.getDrawVertexData(
                    allocator,
                    preview,
                );
                const bounds = shape.getBoundsWithPadding();
                if (option_vertex_data) |vertex_data| {
                    const box_vertex = [6]types.PointUV{
                        // First triangle
                        bounds[0],
                        bounds[1],
                        bounds[2],
                        // Second triangle
                        bounds[2],
                        bounds[3],
                        bounds[0],
                    };
                    web_gpu_programs.draw_shape(&box_vertex, vertex_data.uniform);
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

    // if (state.tool == Tool.DrawShape) {
    if (getSelectedShape()) |shape| {
        const vertex_data = try shape.getSkeletonDrawVertexData(
            allocator,
            state.preview_point,
            state.is_handle_preview,
        );
        web_gpu_programs.draw_triangle(vertex_data);
    }
    // }

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

pub fn renderPick() void {
    if (state.tool == Tool.DrawShape) {
        // TODO: draw selected shape path control points only
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
                const vertex_data = shape.getCacheTexturePickVertexData();
                web_gpu_programs.pick_shape(&vertex_data.bounds, vertex_data.uniforms);
            },
        }
    }

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

pub fn resetAssets(new_assets: []const AssetSerialized, with_snapshot: bool) !void {
    const real_callback_pointer = on_asset_update_cb;
    on_asset_update_cb = null;

    state.preview_point = null;
    state.active_path_index = null;
    state.is_handle_preview = false;

    state.assets.clearAndFree();

    for (new_assets) |asset| {
        switch (asset) {
            .img => |img| {
                try addImage(img.id, img.points, img.texture_id);
            },
            .shape => |shape| {
                const cache = shape.cache orelse shapes.TextureCache{
                    .id = create_cache_texture_callback(),
                };
                _ = try addShape(shape.id, shape.paths, shape.bounds, shape.props, cache);
            },
        }
    }

    if (!state.assets.contains(state.selected_asset_id)) {
        try updateSelectedAsset(NO_SELECTION);
    }

    on_asset_update_cb = real_callback_pointer;

    try checkAssetsUpdate(with_snapshot);
}

pub fn destroyState() void {
    state.assets.clearAndFree();
    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = &.{};
    Msdf.deinitIcons();
    state.selected_asset_id = 0;
    next_asset_id = ASSET_ID_TRESHOLD;
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

fn test_compare() void {
    const pointsA = [_]types.PointUV{
        types.PointUV{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
        types.PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
        types.PointUV{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
        types.PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
    };
    const pointsB = [_]types.PointUV{
        types.PointUV{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
        types.PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
        types.PointUV{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
        types.PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
    };
    std.debug.print("points: {any}\n", .{std.meta.eql(pointsA, pointsB)});

    const cacheA = shapes.TextureCache{
        .id = 1,
        .points = pointsA,
        .width = 100.0,
        .height = 100.0,
    };
    const cacheB = shapes.TextureCache{
        .id = 1,
        .points = pointsB,
        .width = 100.0,
        .height = 100.0,
    };
    std.debug.print("caches: {any}\n", .{std.meta.eql(cacheA, cacheB)});
}
