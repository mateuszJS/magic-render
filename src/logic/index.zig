const std = @import("std");
const Types = @import("./types.zig");
const Texture = @import("./texture.zig").Texture;
const Line = @import("./line.zig").Line;
const LINE_NUM_VERTICIES = @import("./line.zig").LINE_NUM_VERTICIES;
const TransformUI = @import("./transform_ui.zig");
const zigar = @import("zigar");

const WebGpuPrograms = struct {
    draw_texture: *const fn ([]const f32, u32) void,
    draw_triangle: *const fn ([]const f32) void,
    pick_texture: *const fn ([]const f32, u32) void,
    pick_triangle: *const fn ([]const f32) void,
};
var web_gpu_programs: *const WebGpuPrograms = undefined;
// var callback: *const Callback = &none;

pub fn connectWebGPUPrograms(programs: *const WebGpuPrograms) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion
    // callback = cb orelse &none;
    web_gpu_programs = programs; // orelse WebGpuPrograms{};
}

var on_asset_update_cb: *const fn ([]Texture) void = undefined;
pub fn connectOnAssetUpdateCallback(cb: *const fn ([]Texture) void) void {
    on_asset_update_cb = cb;
}

pub const ASSET_ID_TRESHOLD: u32 = 1000;

const ActionType = enum {
    move,
    none,
    transform,
};

const State = struct {
    width: u32,
    height: u32,
    assets: std.AutoHashMap(u32, Texture),
    hovered_asset_id: u32,
    active_asset_id: u32,
    ongoing_action: ActionType,
    last_pointer_coords: Types.Point,
};

var state = State{
    .width = 0,
    .height = 0,
    .assets = std.AutoHashMap(u32, Texture).init(std.heap.page_allocator),
    .hovered_asset_id = 0,
    .active_asset_id = 0,
    .ongoing_action = ActionType.none,
    .last_pointer_coords = Types.Point{ .x = 0.0, .y = 0.0 },
};

pub fn init_state(width: u32, height: u32) void {
    state.width = width;
    state.height = height;
}

pub fn add_texture(id: u32, points: [4]Types.PointUV, texture_id: u32) void {
    state.assets.put(id, Texture.new(id, points, texture_id)) catch unreachable;
}

pub fn update_points(id: u32, points: [4]Types.PointUV) void {
    var asset_ptr: *Texture = state.assets.getPtr(id).?;
    asset_ptr.update_coords(points);
}

pub fn on_update_pick(id: u32) void {
    if (state.ongoing_action != .transform) {
        state.hovered_asset_id = id;
        // hovered_asset_id stores id of the ui transform element during transformations
    }
}

pub fn on_pointer_down(x: f32, y: f32) void {
    if (state.active_asset_id == 0) {
        // No active asset, do nothing
    } else if (TransformUI.is_transform_ui(state.hovered_asset_id)) {
        state.ongoing_action = .transform;
    } else if (state.active_asset_id >= ASSET_ID_TRESHOLD and state.active_asset_id == state.hovered_asset_id) {
        state.ongoing_action = .move;
        state.last_pointer_coords = Types.Point{ .x = x, .y = y };
    }
}

pub fn on_pointer_up() void {
    if (state.ongoing_action == .none) {
        state.active_asset_id = state.hovered_asset_id;
    }

    state.ongoing_action = .none;

    var result = std.heap.page_allocator.alloc(Texture, state.assets.count()) catch unreachable;
    var iterator = state.assets.iterator();
    var i: usize = 0;
    while (iterator.next()) |entry| {
        result[i] = entry.value_ptr.*;
        i += 1;
    }

    if (result.len > 0) {
        on_asset_update_cb(result);
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

            const asset_ptr: *Texture = state.assets.getPtr(state.active_asset_id).?;

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
            const asset_ptr: *Texture = state.assets.getPtr(state.active_asset_id).?;
            const points_ptr: *[4]Types.PointUV = &asset_ptr.points;
            TransformUI.tranform_points(state.hovered_asset_id, points_ptr, x, y);
        },
        .none => {},
    }
}

fn get_border() []f32 {
    var vertex_data = std.ArrayList(f32).init(std.heap.page_allocator);

    // TODO: free memory, defer list.deinit();
    const red = [_]f32{ 1.0, 0.0, 0.0, 1.0 };
    if (state.hovered_asset_id != state.active_asset_id) {
        if (state.assets.get(state.hovered_asset_id)) |asset| {
            for (asset.points, 0..) |point, i| {
                const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];
                var buffer: [LINE_NUM_VERTICIES]f32 = undefined;

                Line.get_vertex_data(
                    // buffer[0..LINE_NUM_VERTICIES],
                    buffer[0..][0..LINE_NUM_VERTICIES],
                    point,
                    next_point,
                    10.0,
                    red,
                );

                vertex_data.appendSlice(&buffer) catch unreachable;
            }
        }
    }

    const green = [_]f32{ 0.0, 1.0, 0.0, 1.0 };
    if (state.assets.get(state.active_asset_id)) |asset| {
        for (asset.points, 0..) |point, i| {
            const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];
            var buffer: [LINE_NUM_VERTICIES]f32 = undefined;
            Line.get_vertex_data(
                buffer[0..LINE_NUM_VERTICIES],
                point,
                next_point,
                10.0,
                green,
            );
            vertex_data.appendSlice(&buffer) catch unreachable;
        }

        var buffer2: [TransformUI.BORDER_BUFFER_SIZE]f32 = undefined;
        TransformUI.get_transform_ui(buffer2[0..TransformUI.BORDER_BUFFER_SIZE], asset, state.hovered_asset_id);
        vertex_data.appendSlice(&buffer2) catch unreachable;
    }

    return vertex_data.items;
}

pub fn canvas_render() void {
    var iterator = state.assets.iterator();

    while (iterator.next()) |asset| {
        const vertex_data = asset.value_ptr.get_vertex_data();

        web_gpu_programs.draw_texture(vertex_data, asset.value_ptr.texture_id);
    }

    const border_verticies = get_border();
    if (border_verticies.len > 0) {
        web_gpu_programs.draw_triangle(border_verticies);
    }
}

pub fn picks_render() void {
    var iterator = state.assets.iterator();

    while (iterator.next()) |asset| {
        const vertex_data = asset.value_ptr.get_vertex_pick_data();

        web_gpu_programs.pick_texture(vertex_data, asset.value_ptr.texture_id);
    }

    if (state.assets.get(state.active_asset_id)) |asset| {
        var vertex_buffer: [TransformUI.PICK_BORDER_BUFFER_SIZE]f32 = undefined;
        TransformUI.get_transform_ui_pick(vertex_buffer[0..TransformUI.PICK_BORDER_BUFFER_SIZE], asset);
        web_gpu_programs.pick_triangle(vertex_buffer[0..TransformUI.PICK_BORDER_BUFFER_SIZE]);
    }
}
