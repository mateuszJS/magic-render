const std = @import("std");
const Types = @import("./types.zig");
const Assets = @import("./assets.zig");
const Line = @import("line.zig");
const Triangle = @import("triangle.zig");
const TransformUI = @import("./transform_ui.zig");
const zigar = @import("zigar");
const Msdf = @import("./msdf.zig");
const SvgTextures = @import("./svg_textures.zig");
const Shapes = @import("./shapes/shapes.zig");

const WebGpuPrograms = struct {
    draw_texture: *const fn ([]const Assets.RenderVertex, u32) void,
    draw_triangle: *const fn ([]const Triangle.DrawInstance) void,
    draw_shape: *const fn ([]const Types.Point, []const Types.Point, Shapes.Uniform) void,
    draw_msdf: *const fn ([]const Msdf.DrawInstance, u32) void,
    pick_texture: *const fn ([]const Assets.PickVertex, u32) void,
    pick_triangle: *const fn ([]const Triangle.PickInstance) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;

pub fn connect_web_gpu_programs(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

var on_asset_update_cb: ?*const fn ([]const Assets.SerializedAsset) void = undefined;
pub fn connect_on_asset_update_callback(cb: *const fn ([]const Assets.SerializedAsset) void) void {
    on_asset_update_cb = cb;
}

fn on_asset_update_noop(_: []const Assets.SerializedAsset) void {}

var on_asset_select_cb: *const fn (u32) void = undefined;
pub fn connect_on_asset_selection_callback(cb: *const fn (u32) void) void {
    on_asset_select_cb = cb;
}

pub const ASSET_ID_TRESHOLD: u32 = 1000;

const ActionType = enum {
    move,
    none,
    transform,
};

const State = struct {
    width: f32,
    height: f32,
    assets: std.AutoArrayHashMap(u32, Assets.Asset),
    hovered_asset_id: u32,
    selected_asset_id: u32,
    ongoing_action: ActionType,
    last_pointer_coords: Types.Point,
    render_scale: f32,
};

var state = State{
    .width = 0,
    .height = 0,
    .assets = undefined,
    .hovered_asset_id = 0,
    .selected_asset_id = 0,
    .ongoing_action = ActionType.none,
    .last_pointer_coords = Types.Point{ .x = 0.0, .y = 0.0 },
    .render_scale = 1.0,
};

pub fn init_state(width: f32, height: f32) void {
    state.width = width;
    state.height = height;
    state.assets = std.AutoArrayHashMap(u32, Assets.Asset).init(std.heap.page_allocator);
}

pub fn init_svg_textures(texture_max_size: f32, resize_texture: *const fn (u32, f32, f32) void) void {
    SvgTextures.init(texture_max_size, resize_texture);
}

pub fn add_svg_texture(texture_id: u32, width: f32, height: f32) void {
    SvgTextures.add_texture(texture_id, width, height);

    // When loading SVG, firstly assets will be added with their texture ID and later texture will load(so we know its svg)
    // and now we have to make sure SVG texture is big enough to match quality of each of the assets.
    var iterator = state.assets.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.texture_id == texture_id) {
            SvgTextures.ensure_svg_texture_quality(entry.value_ptr.*);
        }
    }
}

pub fn update_render_scale(scale: f32) void {
    state.render_scale = scale;
    SvgTextures.update_render_scale(scale);
}

var next_asset_id: u32 = ASSET_ID_TRESHOLD;
fn generate_id() u32 {
    const id = next_asset_id;
    next_asset_id +%= 1;
    return id;
}

pub fn add_asset(id_or_zero: u32, points: [4]Types.PointUV, texture_id: u32) void {
    const id = if (id_or_zero == 0) generate_id() else id_or_zero;
    state.assets.put(id, Assets.Asset.new(id, points, texture_id)) catch unreachable;
    check_assets_update(true);

    const asset_ptr = state.assets.getPtr(id) orelse unreachable;
    SvgTextures.ensure_svg_texture_quality(asset_ptr.*);
}

pub fn remove_asset() void {
    _ = state.assets.orderedRemove(state.selected_asset_id);
    state.selected_asset_id = 0;
    on_asset_select_cb(state.selected_asset_id);
    check_assets_update(true);
}

pub fn on_update_pick(id: u32) void {
    if (state.ongoing_action != .transform) {
        state.hovered_asset_id = id;
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

pub fn on_pointer_down(x: f32, y: f32) void {
    if (state.selected_asset_id == 0) {
        // No active asset, do nothing
    } else if (TransformUI.is_transform_ui(state.hovered_asset_id)) {
        state.ongoing_action = .transform;
    } else if (state.selected_asset_id >= ASSET_ID_TRESHOLD and state.selected_asset_id == state.hovered_asset_id) {
        state.ongoing_action = .move;
        state.last_pointer_coords = Types.Point{ .x = x, .y = y };
    }
}

// const std.heap.page_allocator.alloc(SerializedAsset, state.assets.count())
var last_assets_update: []const Assets.SerializedAsset = &.{};
fn check_assets_update(should_notify: bool) void {
    const cb = on_asset_update_cb orelse return;

    var new_assets_update = std.heap.page_allocator.alloc(Assets.SerializedAsset, state.assets.count()) catch unreachable;
    var iterator = state.assets.iterator();
    var i: usize = 0;
    while (iterator.next()) |entry| {
        new_assets_update[i] = entry.value_ptr.serialize();
        i += 1;
    }

    if (new_assets_update.len == last_assets_update.len) {
        var all_match = true;
        for (new_assets_update, 0..) |new_asset, j| {
            if (!std.meta.eql(new_asset, last_assets_update[j])) {
                all_match = false;
                break;
            }
        }

        if (all_match) {
            std.heap.page_allocator.free(new_assets_update);
            return;
        }
    }

    std.heap.page_allocator.free(last_assets_update);
    last_assets_update = new_assets_update;

    if (should_notify) {
        if (new_assets_update.len > 0) {
            cb(new_assets_update); // would throw error if results.len == 0
        } else {
            cb(&.{});
        }
    }
}

pub fn on_pointer_up() void {
    if (state.ongoing_action == .none) {
        state.selected_asset_id = state.hovered_asset_id;
        on_asset_select_cb(state.selected_asset_id);
    } else {
        state.ongoing_action = .none;
        check_assets_update(true);
    }
}

pub fn on_pointer_move(x: f32, y: f32) void {
    switch (state.ongoing_action) {
        .move => {
            const offset = Types.Point{
                .x = x - state.last_pointer_coords.x,
                .y = y - state.last_pointer_coords.y,
            };
            state.last_pointer_coords = Types.Point{ .x = x, .y = y };

            const asset_ptr: *Assets.Asset = state.assets.getPtr(state.selected_asset_id).?;

            var new_points: [4]Types.PointUV = undefined;
            for (asset_ptr.points, 0..) |point, i| {
                new_points[i] = Types.PointUV{
                    .x = point.x + offset.x,
                    .y = point.y + offset.y,
                    .u = point.u,
                    .v = point.v,
                };
            }

            asset_ptr.update_coords(new_points);
        },
        .transform => {
            const asset_ptr: *Assets.Asset = state.assets.getPtr(state.selected_asset_id).?;
            const points_ptr: *[4]Types.PointUV = &asset_ptr.points;
            TransformUI.tranform_points(state.hovered_asset_id, points_ptr, x, y);
            SvgTextures.ensure_svg_texture_quality(asset_ptr.*);
        },
        .none => {},
    }
}

pub fn on_pointer_leave() void {
    state.ongoing_action = .none;
    state.hovered_asset_id = 0;
    check_assets_update(true);
}

fn get_border() struct { []Triangle.DrawInstance, []Msdf.DrawInstance } {
    var triangle_vertex_data = std.ArrayList(Triangle.DrawInstance).init(std.heap.page_allocator);
    var msdf_vertex_data = std.ArrayList(Msdf.DrawInstance).init(std.heap.page_allocator);

    defer triangle_vertex_data.deinit();
    defer msdf_vertex_data.deinit();

    const red = [_]u8{ 255, 0, 0, 255 };
    if (state.hovered_asset_id != state.selected_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            for (asset.points, 0..) |point, i| {
                const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];
                var buffer: [2]Triangle.DrawInstance = undefined;

                Line.get_draw_vertex_data(
                    buffer[0..2],
                    point,
                    next_point,
                    10.0 * state.render_scale,
                    red,
                    5.0 * state.render_scale,
                );

                triangle_vertex_data.appendSlice(&buffer) catch unreachable;
            }
        }
    }

    const green = [_]u8{ 0, 255, 0, 255 };
    if (state.assets.get(state.selected_asset_id)) |asset| {
        for (asset.points, 0..) |point, i| {
            const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];
            var buffer: [2]Triangle.DrawInstance = undefined;

            Line.get_draw_vertex_data(
                buffer[0..2],
                point,
                next_point,
                10.0 * state.render_scale,
                green,
                5.0 * state.render_scale,
            );
            triangle_vertex_data.appendSlice(&buffer) catch unreachable;
        }

        var triangle_buffer: [TransformUI.RENDER_TRIANGLE_INSTANCES]Triangle.DrawInstance = undefined;
        var msdf_buffer: [2]Msdf.DrawInstance = undefined;

        TransformUI.get_draw_vertex_data(
            &triangle_buffer,
            &msdf_buffer,
            asset,
            state.hovered_asset_id,
            state.render_scale,
        );

        triangle_vertex_data.appendSlice(&triangle_buffer) catch unreachable;
        msdf_vertex_data.appendSlice(&msdf_buffer) catch unreachable;
    }

    return .{
        triangle_vertex_data.items,
        msdf_vertex_data.items,
    };
}

fn draw_project_background() void {
    const points = [_]Types.Point{
        Types.Point{ .x = 0.0, .y = 0.0 }, //
        Types.Point{ .x = state.width, .y = 0.0 }, //
        Types.Point{ .x = state.width, .y = state.height }, //
        Types.Point{ .x = 0.0, .y = state.height }, //
    };
    const p0_v = Triangle.get_round_corner_vector(0, points, 0.0);
    const p1_v = Triangle.get_round_corner_vector(1, points, 0.0);
    const p2_v = Triangle.get_round_corner_vector(2, points, 0.0);
    const p3_v = Triangle.get_round_corner_vector(3, points, 0.0);

    const color = [_]u8{ 30, 30, 30, 255 }; // gray color

    var buffer: [2]Triangle.DrawInstance = undefined;
    Triangle.get_draw_vertex_data(buffer[0..1], p0_v, p1_v, p2_v, color);
    Triangle.get_draw_vertex_data(buffer[1..2], p0_v, p2_v, p3_v, color);

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
            2.0 * state.render_scale,
            color,
            0.0,
        );
    }

    web_gpu_programs.draw_triangle(&buffer);
}

pub fn render_draw(allocator: std.mem.Allocator) void {
    draw_project_background();

    var iterator = state.assets.iterator();

    while (iterator.next()) |asset| {
        var vertex_data: [6]Assets.RenderVertex = undefined;
        asset.value_ptr.get_render_vertex_data(&vertex_data);
        web_gpu_programs.draw_texture(&vertex_data, asset.value_ptr.texture_id);
    }

    draw_project_boundary();

    const triangle_buffer, const msdf_buffer = get_border();
    if (triangle_buffer.len > 0) {
        web_gpu_programs.draw_triangle(triangle_buffer);
    }
    if (msdf_buffer.len > 0) {
        web_gpu_programs.draw_msdf(msdf_buffer, 0);
    }

    // Define cubic Bézier curves that form the shape boundary
    const curves = [_]Types.Point{
        .{ .x = 100, .y = 0 },
        .{ .x = 300, .y = 400 },
        .{ .x = 600, .y = 600 },
        .{ .x = 500, .y = 100 },
        .{ .x = 300, .y = -200 },
        .{ .x = 400, .y = -300 },
        .{ .x = 100, .y = 0 },
    };
    const shape = Shapes.Shape.init(31, &curves, allocator) catch unreachable;
    // defer shape.deinit(); // Free the shape itself

    const shape_vertex_data = shape.get_draw_vertex_data(allocator) catch unreachable;
    // defer allocator.free(shape_vertex_data.curves); // Free the curves slice
    // defer allocator.free(shape_vertex_data.bounding_box); // Free the bounding_box slice

    web_gpu_programs.draw_shape(shape_vertex_data.curves, &shape_vertex_data.bounding_box, shape_vertex_data.uniform);

    // shape_vertex_data.curves[0].x = -200;
    // shape_vertex_data.curves[0].y = -200;
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
        var vertex_data: [6]Assets.PickVertex = undefined;
        asset.value_ptr.get_pick_vertex_data(&vertex_data);

        web_gpu_programs.pick_texture(&vertex_data, asset.value_ptr.texture_id);
    }

    if (state.assets.get(state.selected_asset_id)) |asset| {
        var vertex_buffer: [TransformUI.PICK_TRIANGLE_INSTANCES]Triangle.PickInstance = undefined;
        TransformUI.get_pick_vertex_data(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES], asset, state.render_scale);
        web_gpu_programs.pick_triangle(vertex_buffer[0..TransformUI.PICK_TRIANGLE_INSTANCES]);
    }
}

pub fn reset_assets(new_assets: []const Assets.SerializedAsset, with_snapshot: bool) void {
    const real_callback_pointer = on_asset_update_cb;
    on_asset_update_cb = null;

    state.assets.clearAndFree();

    for (new_assets) |asset| {
        add_asset(asset.id, asset.points, asset.texture_id);
    }

    if (!state.assets.contains(state.selected_asset_id)) {
        state.selected_asset_id = 0;
        on_asset_select_cb(state.selected_asset_id);
    }

    on_asset_update_cb = real_callback_pointer;

    check_assets_update(with_snapshot);
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

        fn assets_update(_: []const Assets.SerializedAsset) void {
            // Modify the static variable within the struct.
            was_called = true;
        }

        fn assets_selection(_: u32) void {}
    };

    // Connect our mock callback. This is the "real" callback for this test.
    connect_on_asset_update_callback(MockCallback.assets_update);
    connect_on_asset_selection_callback(MockCallback.assets_selection);

    // Call the function we are testing
    const initial_assets = [_]Assets.SerializedAsset{.{
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
