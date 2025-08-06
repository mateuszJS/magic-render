const std = @import("std");
const types = @import("./types.zig");
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
    draw_texture: *const fn (shapes.TextureDrawVertex, u32) void,
    draw_triangle: *const fn ([]const Triangle.DrawInstance) void,
    draw_shape: *const fn ([]const types.Point, []const types.Point, shapes.Uniform) void,
    draw_msdf: *const fn ([]const Msdf.DrawInstance, u32) void,
    pick_texture: *const fn ([]const shapes.TexturePickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;

pub fn connectWebGpuPrograms(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

var on_asset_update_cb: ?*const fn ([]const shapes.Serialized) void = undefined;
pub fn connectOnAssetUpdateCallback(cb: *const fn ([]const shapes.Serialized) void) void {
    on_asset_update_cb = cb;
}

var on_asset_select_cb: *const fn (u32) void = undefined;
pub fn connectOnAssetSelectionCallback(cb: *const fn (u32) void) void {
    on_asset_select_cb = cb;
}

var start_cache_callback: *const fn (?u32, bounding_box.BoundingBox, f32, f32) u32 = undefined;
var end_cache_callback: *const fn () void = undefined;

pub fn connectCacheCallbacks(start_cache: *const fn (?u32, bounding_box.BoundingBox, f32, f32) u32, end_cache: *const fn () void) void {
    start_cache_callback = start_cache;
    end_cache_callback = end_cache;

    shapes.cacheShape = cache_shape_cb;
}

fn cache_shape_cb(curr_texture_id: ?u32, box: bounding_box.BoundingBox, vertex_data: shapes.VectorDrawVertex, width: f32, height: f32) u32 {
    const texture_id = start_cache_callback(curr_texture_id, box, width, height);
    web_gpu_programs.draw_shape(vertex_data.curves, &vertex_data.bounding_box, vertex_data.uniform);
    end_cache_callback();
    return texture_id;
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

const State = struct {
    width: f32,
    height: f32,
    assets: std.AutoArrayHashMap(u32, shapes.Shape),
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
    state.assets = std.AutoArrayHashMap(u32, shapes.Shape).init(std.heap.page_allocator);
    shapes.maxTextureSize = texture_max_size;
}

pub fn updateRenderScale(scale: f32) !void {
    shared.render_scale = scale;

    var iterator = state.assets.iterator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    while (iterator.next()) |entry| {
        const asset = entry.value_ptr;
        if (asset.updateTextureSize()) {
            try asset.drawTextureCache(allocator, true);
        }
    }
}

var next_asset_id: u32 = ASSET_ID_TRESHOLD;
fn generateId() u32 {
    const id = next_asset_id;
    next_asset_id +%= 1;
    return id;
}

pub fn addAsset(id_or_zero: u32, points: [4]types.PointUV, texture_id: u32) !void {
    const id = if (id_or_zero == 0) generateId() else id_or_zero;
    const asset = shapes.Shape.newFromTexture(id, points, texture_id);
    try state.assets.put(id, asset);

    try checkAssetsUpdate(true);
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

var last_assets_update: []const shapes.Serialized = &.{};
fn checkAssetsUpdate(should_notify: bool) !void {
    const cb = on_asset_update_cb orelse return;

    var new_assets_update = std.ArrayList(shapes.Serialized).init(std.heap.page_allocator);
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset_entry| {
        const serialized = try asset_entry.value_ptr.serialize();
        try new_assets_update.append(serialized);
    }

    if (new_assets_update.items.len == last_assets_update.len) {
        var all_match = true;
        for (new_assets_update.items, 0..) |new_asset, i| {
            if (!std.meta.eql(new_asset, last_assets_update[i])) {
                all_match = false;
                break;
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

fn updateSelectedAsset(id: u32) !void {
    try commitChanges();
    state.selected_asset_id = id;
    on_asset_select_cb(id);
}

pub fn onPointerDown(_allocator: std.mem.Allocator, x: f32, y: f32) !void {
    _ = _allocator; // autofix
    if (state.tool == Tool.DrawShape) {
        const preview_point = types.Point{ .x = x, .y = y };
        state.preview_point = preview_point;

        if (state.selected_asset_id == NO_SELECTION) {
            const id = generateId();
            const shape = try shapes.Shape.new(
                id,
                std.heap.page_allocator,
            );
            try state.assets.put(id, shape);
            try updateSelectedAsset(id);
        }

        if (state.assets.getPtr(state.selected_asset_id)) |shape| {
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
            const shape = state.assets.getPtr(state.selected_asset_id) orelse @panic("Selected shape asset should be present when active_path_index is not null");
            if (shape.paths.items[active_path_index].closed) {
                state.active_path_index = null;
            }
        }
        state.is_handle_preview = false;
    }
}

pub fn onPointerMove(x: f32, y: f32) void {
    if (state.tool == Tool.DrawShape) {
        if (state.assets.getPtr(state.selected_asset_id)) |shape| {
            const preview_point = types.Point{ .x = x, .y = y };
            state.preview_point = preview_point;

            if (state.active_path_index) |active_path_index| {
                if (state.is_handle_preview) {
                    shape.updateLastHandle(active_path_index, preview_point);
                }
            }
        }

        return;
    }

    if (state.assets.getPtr(state.selected_asset_id)) |img| {
        switch (state.action) {
            .Move => {
                const offset = types.Point{
                    .x = x - state.last_pointer_coords.x,
                    .y = y - state.last_pointer_coords.y,
                };
                state.last_pointer_coords = types.Point{ .x = x, .y = y };

                var new_points: [4]types.PointUV = undefined;
                for (img.box, 0..) |point, i| {
                    new_points[i] = types.PointUV{
                        .x = point.x + offset.x,
                        .y = point.y + offset.y,
                        .u = point.u,
                        .v = point.v,
                    };
                }

                img.updateBox(new_points);
            },
            .Transform => {
                const points_ptr: *[4]types.PointUV = &img.box;
                TransformUI.transformPoints(state.hovered_asset_id, points_ptr, x, y);
            },
            .None => {},
        }
    }
}

pub fn onPointerLeave() !void {
    state.action = .None;
    state.hovered_asset_id = 0;
    try checkAssetsUpdate(true);
}

fn updateShapeCache(shape: *shapes.Shape) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try shape.drawTextureCache(allocator, false);
}

pub fn commitChanges() !void {
    if (state.tool == Tool.DrawShape) {
        if (state.assets.getPtr(state.selected_asset_id)) |shape| {
            try updateShapeCache(shape);
        }
    }
}

fn getBorder(allocator: std.mem.Allocator) struct { []Triangle.DrawInstance, []Msdf.DrawInstance } {
    var triangle_vertex_data = std.ArrayList(Triangle.DrawInstance).init(allocator);
    var msdf_vertex_data = std.ArrayList(Msdf.DrawInstance).init(allocator);

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id != state.selected_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            for (asset.box, 0..) |point, i| {
                const next_point = if (i == 3) asset.box[0] else asset.box[i + 1];
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
        for (asset.box, 0..) |point, i| {
            const next_point = if (i == 3) asset.box[0] else asset.box[i + 1];
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
            asset.box,
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

const point_size: f32 = @floatFromInt(@sizeOf(types.Point)); // 8 bytes
const triangle_size: f32 = @floatFromInt(@sizeOf(Triangle.DrawInstance)); // 64 bytes
// const asset_size: f32 = @floatFromInt(@sizeOf(shapes.DrawVertex)); // 96 bytes

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
    // std.debug.print("assets length: {d}\n", .{state.assets.count()});
    while (iterator.next()) |entry| {
        const asset = entry.value_ptr.*;
        if (asset.texture_id) |texture_id| {
            var vertex_data: shapes.TextureDrawVertex = undefined;
            asset.getTextureRenderVertexData(&vertex_data);
            web_gpu_programs.draw_texture(vertex_data, texture_id);
        } else {
            std.debug.print("Asset has no texture_id\n", .{});
            const option_vertex_data = try asset.getDrawVertexData(
                allocator,
                state.active_path_index,
                state.preview_point,
            );
            if (option_vertex_data) |vertex_data| {
                web_gpu_programs.draw_shape(vertex_data.curves, &vertex_data.bounding_box, vertex_data.uniform);
            }
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

    if (state.tool == Tool.DrawShape) {
        if (state.assets.getPtr(state.selected_asset_id)) |shape| {
            const vertex_data = shape.getSkeletonDrawVertexData(allocator, state.preview_point, state.is_handle_preview) catch unreachable;
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

pub fn renderPick() void {
    var iterator = state.assets.iterator();
    while (iterator.next()) |entry| {
        const asset = entry.value_ptr.*;
        if (asset.texture_id) |texture_id| {
            var vertex_data: [6]shapes.TexturePickVertex = undefined;
            asset.getTexturePickVertexData(&vertex_data);
            web_gpu_programs.pick_texture(&vertex_data, texture_id);
        }
    }

    if (state.assets.get(state.selected_asset_id)) |asset| {
        var vertex_buffer: [TransformUI.PICK_TRIANGLE_INSTANCES]Triangle.PickInstance = undefined;
        TransformUI.getPickVertexData(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES], asset.box);
        web_gpu_programs.pick_triangle(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES]);
    }
}

pub fn resetAssets(new_assets: []const shapes.Serialized, with_snapshot: bool) !void {
    const real_callback_pointer = on_asset_update_cb;
    on_asset_update_cb = null;

    state.assets.clearAndFree();

    for (new_assets) |asset| {
        try addAsset(asset.id, asset.box, asset.texture_id);
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

pub fn addShape(paths: []const []const [4]types.Point, props: shapes.ShapeProps) !void {
    const id = generateId();
    const shape = try shapes.Shape.newFromPoints(id, paths, props, std.heap.page_allocator);
    try state.assets.put(id, shape);
    state.selected_asset_id = id;
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

        fn assets_update(_: []const shapes.Serialized) void {
            // Modify the static variable within the struct.
            was_called = true;
        }

        fn assets_selection(_: u32) void {}
    };

    // Connect our mock callback. This is the "real" callback for this test.
    connectOnAssetUpdateCallback(MockCallback.assets_update);
    connectOnAssetSelectionCallback(MockCallback.assets_selection);

    // Call the function we are testing
    const initial_assets = [_]shapes.Serialized{.{
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

    // for the duration of reset_assets, the update callback should NOT be called
    try std.testing.expect(!MockCallback.was_called);
}
