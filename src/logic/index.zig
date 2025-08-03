const std = @import("std");
const Types = @import("./types.zig");
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
    draw_shape: *const fn ([]const Types.Point, []const Types.Point, shapes.Uniform) void,
    draw_msdf: *const fn ([]const Msdf.DrawInstance, u32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;

pub fn connect_web_gpu_programs(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

var on_asset_update_cb: ?*const fn ([]const images.Serialized) void = undefined;
pub fn connect_on_asset_update_callback(cb: *const fn ([]const images.Serialized) void) void {
    on_asset_update_cb = cb;
}

fn on_asset_update_noop(_: []const images.Serialized) void {}

var on_asset_select_cb: *const fn (u32) void = undefined;
pub fn connect_on_asset_selection_callback(cb: *const fn (u32) void) void {
    on_asset_select_cb = cb;
}

var start_cache_callback: *const fn (?u32, bounding_box.BoundingBox, f32, f32) u32 = undefined;
var end_cache_callback: *const fn () void = undefined;

pub fn connect_cache_callbacks(start_cache: *const fn (?u32, bounding_box.BoundingBox, f32, f32) u32, end_cache: *const fn () void) void {
    start_cache_callback = start_cache;
    end_cache_callback = end_cache;

    shapes.cache_shape = cache_shape_cb;
}

fn cache_shape_cb(curr_texture_id: ?u32, box: bounding_box.BoundingBox, vertex_data: shapes.DrawVertexOutput, width: f32, height: f32) u32 {
    const texture_id = start_cache_callback(curr_texture_id, box, width, height);
    web_gpu_programs.draw_shape(vertex_data.curves, &vertex_data.bounding_box, vertex_data.uniform);
    end_cache_callback();
    return texture_id;
}

pub const ASSET_ID_TRESHOLD: u32 = 1000;

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

const State = struct {
    width: f32,
    height: f32,
    assets: std.AutoArrayHashMap(u32, Asset),
    hovered_asset_id: u32,
    selected_asset_id: u32,
    action: ActionType,
    tool: Tool,
    last_pointer_coords: Types.Point,
};

var state = State{
    .width = 0,
    .height = 0,
    .assets = undefined,
    .hovered_asset_id = 0,
    .selected_asset_id = 0,
    .action = ActionType.None,
    .tool = Tool.None,
    .last_pointer_coords = Types.Point{ .x = 0.0, .y = 0.0 },
};

pub fn init_state(allocator: std.mem.Allocator, width: f32, height: f32, texture_max_size: f32) void {
    _ = allocator; // autofix
    state.width = width;
    state.height = height;
    state.assets = std.AutoArrayHashMap(u32, Asset).init(std.heap.page_allocator);
    shapes.max_texture_size = texture_max_size;
}

pub fn update_render_scale(scale: f32) !void {
    shared.render_scale = scale;

    var iterator = state.assets.iterator();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => {},
            .shape => |*shape| {
                if (shape.updateTextureSize()) {
                    try shape.drawTextureCache(allocator);
                }
            },
        }
    }
}

var next_asset_id: u32 = ASSET_ID_TRESHOLD;
fn generate_id() u32 {
    const id = next_asset_id;
    next_asset_id +%= 1;
    return id;
}

pub fn add_asset(id_or_zero: u32, points: [4]Types.PointUV, texture_id: u32) !void {
    const id = if (id_or_zero == 0) generate_id() else id_or_zero;
    const asset = Asset{
        .img = images.Image.new(id, points, texture_id),
    };
    try state.assets.put(id, asset);

    try check_assets_update(true);
}

pub fn remove_asset() !void {
    _ = state.assets.orderedRemove(state.selected_asset_id);
    state.selected_asset_id = 0;
    on_asset_select_cb(state.selected_asset_id);
    try check_assets_update(true);
}

pub fn on_update_pick(id: u32) void {
    if (state.action != .Transform) {
        state.hovered_asset_id = id;
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

var last_assets_update: []const images.Serialized = &.{};
fn check_assets_update(should_notify: bool) !void {
    const cb = on_asset_update_cb orelse return;

    var new_assets_update = std.ArrayList(images.Serialized).init(std.heap.page_allocator);
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset_entry| {
        switch (asset_entry.value_ptr.*) {
            .img => |img| {
                try new_assets_update.append(img.serialize());
            },
            .shape => {},
        }
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

fn get_selected_img() ?*images.Image {
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => |*img| return img,
        .shape => return null,
    }
}

fn get_selected_shape() ?*shapes.Shape {
    const asset = state.assets.getPtr(state.selected_asset_id) orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
    }
}

pub fn on_pointer_down(_allocator: std.mem.Allocator, x: f32, y: f32) !void {
    _ = _allocator; // autofix
    if (state.tool == Tool.DrawShape) {
        const point = Types.Point{ .x = x, .y = y };

        if (get_selected_shape()) |shape| {
            shape.setPreviewPoint(point);
            try shape.addPointStart();
            // const is_completed = try shape.addPointStart();
            // if (is_completed) {
            //     // Shape is completed, we can finalize it
            //     var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            //     defer arena.deinit();
            //     const allocator = arena.allocator();

            //     try shape.completeShape(allocator);
            // }
            return;
        }

        const id = generate_id();
        const shape = shapes.Shape.new(
            id,
            point,
            std.heap.page_allocator,
        ) catch unreachable;
        try state.assets.put(id, Asset{ .shape = shape });
        state.selected_asset_id = id;

        return;
    }

    if (state.selected_asset_id == 0) {
        // No active asset, do nothing
    } else if (TransformUI.is_transform_ui(state.hovered_asset_id)) {
        state.action = .Transform;
    } else if (state.selected_asset_id >= ASSET_ID_TRESHOLD and state.selected_asset_id == state.hovered_asset_id) {
        state.action = .Move;
        state.last_pointer_coords = Types.Point{ .x = x, .y = y };
    }
}

pub fn on_pointer_up() !void {
    if (state.tool == .None) {
        if (state.action == .None) {
            state.selected_asset_id = state.hovered_asset_id;
            on_asset_select_cb(state.selected_asset_id);
        } else {
            state.action = .None;
            try check_assets_update(true);
        }
    } else if (state.tool == Tool.DrawShape) {
        if (get_selected_shape()) |shape| {
            try shape.add_point_end();
        }
    }
}

pub fn on_pointer_move(x: f32, y: f32) void {
    if (state.tool == Tool.DrawShape) {
        if (get_selected_shape()) |shape| {
            shape.setPreviewPoint(Types.Point{ .x = x, .y = y });
        }

        return;
    }

    if (get_selected_img()) |img| {
        switch (state.action) {
            .Move => {
                const offset = Types.Point{
                    .x = x - state.last_pointer_coords.x,
                    .y = y - state.last_pointer_coords.y,
                };
                state.last_pointer_coords = Types.Point{ .x = x, .y = y };

                var new_points: [4]Types.PointUV = undefined;
                for (img.points, 0..) |point, i| {
                    new_points[i] = Types.PointUV{
                        .x = point.x + offset.x,
                        .y = point.y + offset.y,
                        .u = point.u,
                        .v = point.v,
                    };
                }

                img.update_coords(new_points);
            },
            .Transform => {
                const points_ptr: *[4]Types.PointUV = &img.points;
                TransformUI.tranform_points(state.hovered_asset_id, points_ptr, x, y);
            },
            .None => {},
        }
    }
}

pub fn on_pointer_leave() !void {
    state.action = .None;
    state.hovered_asset_id = 0;
    try check_assets_update(true);
}

pub fn commitChanges() !void {
    if (state.tool == Tool.DrawShape) {
        if (get_selected_shape()) |shape| {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            try shape.complete(allocator);
        }
    }
}

fn get_border(allocator: std.mem.Allocator) struct { []Triangle.DrawInstance, []Msdf.DrawInstance } {
    var triangle_vertex_data = std.ArrayList(Triangle.DrawInstance).init(allocator);
    var msdf_vertex_data = std.ArrayList(Msdf.DrawInstance).init(allocator);

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id != state.selected_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            switch (asset) {
                .img => |img| {
                    for (img.points, 0..) |point, i| {
                        const next_point = if (i == 3) img.points[0] else img.points[i + 1];
                        var buffer: [2]Triangle.DrawInstance = undefined;

                        Line.get_draw_vertex_data(
                            buffer[0..2],
                            point,
                            next_point,
                            10.0 * shared.render_scale,
                            red,
                            5.0 * shared.render_scale,
                        );

                        triangle_vertex_data.appendSlice(&buffer) catch unreachable;
                    }
                },
                .shape => {},
            }
        }
    }

    const green = [_]u8{ 0, 255, 0, 255 };
    if (state.assets.get(state.selected_asset_id)) |asset| {
        switch (asset) {
            .img => |img| {
                for (img.points, 0..) |point, i| {
                    const next_point = if (i == 3) img.points[0] else img.points[i + 1];
                    var buffer: [2]Triangle.DrawInstance = undefined;

                    Line.get_draw_vertex_data(
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

                TransformUI.get_draw_vertex_data(
                    &triangle_buffer,
                    &msdf_buffer,
                    img,
                    state.hovered_asset_id,
                );

                triangle_vertex_data.appendSlice(&triangle_buffer) catch unreachable;
                msdf_vertex_data.appendSlice(&msdf_buffer) catch unreachable;
            },
            .shape => {},
        }
    }

    return .{
        triangle_vertex_data.items,
        msdf_vertex_data.items,
    };
}

fn draw_project_background() void {
    var buffer: [2]Triangle.DrawInstance = undefined;
    squares.get_draw_vertex_data(
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

fn draw_project_boundary() void {
    var buffer: [2 * 4]Triangle.DrawInstance = undefined;

    const points = [_]Types.Point{
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = state.width, .y = 0.0 },
        .{ .x = state.width, .y = state.height },
        .{ .x = 0.0, .y = state.height },
    };

    const color = [_]u8{ 127, 127, 127, 255 }; // gray color

    for (points, 0..) |point, i| {
        const next_point = if (i == 3) points[0] else points[i + 1];

        Line.get_draw_vertex_data(
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

const point_size: f32 = @floatFromInt(@sizeOf(Types.Point)); // 8 bytes
const triangle_size: f32 = @floatFromInt(@sizeOf(Triangle.DrawInstance)); // 64 bytes
const asset_size: f32 = @floatFromInt(@sizeOf(images.DrawVertex)); // 96 bytes

pub fn render_draw() !void {
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

    draw_project_background();

    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: images.DrawVertex = undefined;
                img.get_render_vertex_data(&vertex_data);
                web_gpu_programs.draw_texture(vertex_data, img.texture_id);
            },
            .shape => |shape| {
                if (shape.texture_id) |texture_id| {
                    const vertex_data = images.DrawVertex{
                        // first triangle
                        .{ .x = shape.bounding_box.min_x, .y = shape.bounding_box.min_y, .u = 0.0, .v = 0.0 }, // Assuming texture coordinates start at (0, 0)
                        .{ .x = shape.bounding_box.min_x, .y = shape.bounding_box.max_y, .u = 0.0, .v = 1.0 }, // Top-right
                        .{ .x = shape.bounding_box.max_x, .y = shape.bounding_box.max_y, .u = 1.0, .v = 1.0 }, // Bottom-right
                        // second triangle
                        .{ .x = shape.bounding_box.max_x, .y = shape.bounding_box.max_y, .u = 1.0, .v = 1.0 }, // Bottom-right
                        .{ .x = shape.bounding_box.max_x, .y = shape.bounding_box.min_y, .u = 1.0, .v = 0.0 }, // Closing the rectangle
                        .{ .x = shape.bounding_box.min_x, .y = shape.bounding_box.min_y, .u = 0.0, .v = 0.0 }, // Top-right
                    };
                    web_gpu_programs.draw_texture(vertex_data, texture_id);
                } else {
                    const option_vertex_data = try shape.get_draw_vertex_data(allocator);
                    if (option_vertex_data) |vertex_data| {
                        web_gpu_programs.draw_shape(vertex_data.curves, &vertex_data.bounding_box, vertex_data.uniform);
                    }
                }
            },
        }
    }

    draw_project_boundary(); // TODO: once we support strokes for Triangles, we should use it here wit transparent fill

    const triangle_buffer, const msdf_buffer = get_border(allocator);
    if (triangle_buffer.len > 0) {
        web_gpu_programs.draw_triangle(triangle_buffer);
    }
    if (msdf_buffer.len > 0) {
        web_gpu_programs.draw_msdf(msdf_buffer, 0);
    }

    if (state.tool == Tool.DrawShape) {
        if (get_selected_shape()) |shape| {
            const vertex_data = shape.get_skeleton_draw_vertex_data(allocator) catch unreachable;
            web_gpu_programs.draw_triangle(vertex_data);
        }
    }

    // testing:

    // const points = [_]Types.Point{
    //     Types.Point{ .x = 100.0, .y = 70.0 }, //
    //     Types.Point{ .x = 300.0, .y = 100.0 }, //
    //     Types.Point{ .x = 300.0, .y = 250.0 }, //
    //     Types.Point{ .x = 100.0, .y = 150.0 }, //
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

pub fn render_pick() void {
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset| {
        switch (asset.value_ptr.*) {
            .img => |img| {
                var vertex_data: [6]images.PickVertex = undefined;
                img.get_pick_vertex_data(&vertex_data);

                web_gpu_programs.pick_texture(&vertex_data, img.texture_id);
            },
            .shape => {},
        }
    }

    if (state.assets.get(state.selected_asset_id)) |asset| {
        switch (asset) {
            .img => |img| {
                var vertex_buffer: [TransformUI.PICK_TRIANGLE_INSTANCES]Triangle.PickInstance = undefined;
                TransformUI.get_pick_vertex_data(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES], img);
                web_gpu_programs.pick_triangle(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES]);
            },
            .shape => {},
        }
    }
}

pub fn reset_assets(new_assets: []const images.Serialized, with_snapshot: bool) !void {
    const real_callback_pointer = on_asset_update_cb;
    on_asset_update_cb = null;

    state.assets.clearAndFree();

    for (new_assets) |asset| {
        try add_asset(asset.id, asset.points, asset.texture_id);
    }

    if (!state.assets.contains(state.selected_asset_id)) {
        state.selected_asset_id = 0;
        on_asset_select_cb(state.selected_asset_id);
    }

    on_asset_update_cb = real_callback_pointer;

    try check_assets_update(with_snapshot);
}

pub fn destroy_state() void {
    state.assets.clearAndFree();
    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = &.{};
    Msdf.deinit_icons();
    state.selected_asset_id = 0;
    next_asset_id = ASSET_ID_TRESHOLD;
    web_gpu_programs = undefined;
    on_asset_update_cb = undefined;
    // state itself is not destoyed as it will be reinitalized before usage
    // and has no reference to memory to free
}

pub fn import_icons(data: []const f32) void {
    Msdf.init_icons(data);
}

pub fn set_tool(tool: Tool) !void {
    try commitChanges();
    state.tool = tool;
}

pub fn stop_drawing_shape() void {
    state.selected_asset_id = 0;
}

pub fn add_shape(paths: []const []const [4]Types.Point, props: shapes.ShapeProps) !void {
    const id = generate_id();
    const shape = try shapes.Shape.new_from_points(id, paths, props, std.heap.page_allocator);
    try state.assets.put(id, Asset{ .shape = shape });
    state.selected_asset_id = id;
}

test "reset_assets does not call the real update callback" {
    // Setup initial state
    init_state(100, 100);
    // Ensure state is cleaned up after the test
    defer destroy_state();

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
    connect_on_asset_update_callback(MockCallback.assets_update);
    connect_on_asset_selection_callback(MockCallback.assets_selection);

    // Call the function we are testing
    const initial_assets = [_]images.Serialized{.{
        .points = [_]Types.PointUV{
            Types.PointUV{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
            Types.PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
            Types.PointUV{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
            Types.PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
        },
        .texture_id = 1,
        .id = 123,
    }};
    reset_assets(&initial_assets, false);

    // for the duration of reset_assets, the update callback should NOT be called
    try std.testing.expect(!MockCallback.was_called);
}
