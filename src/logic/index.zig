const std = @import("std");
const Types = @import("./types.zig");
const Texture = @import("./texture.zig").Texture;
const Line = @import("./line.zig").Line;

// const console_log_str = @extern("console_log_str", fn (ptr: [*]const u8, len: usize) void);

// pub fn log(message: []const u8) void {
//     console_log_str(message.ptr, message.len);
// }

// pub fn main() void {
//     log("Hello from Zig!");
// }

const ASSET_ID_TRESHOLD: u32 = 1000;

const ActionType = enum {
    move,
    none,
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

pub fn add_texture(id: u32, points: [4]Types.PointUV, texture_index: u32) !void {
    try state.assets.put(id, Texture.new(id, points, texture_index));
}

pub fn get_shader_input(id: u32) !ShaderInput {
    if (state.assets.get(id)) |asset| {
        const vertex_data = try asset.get_vertex_data();
        return ShaderInput{
            .texture_id = asset.texture_id,
            .vertex_data = vertex_data,
        };
    } else {
        unreachable("asset with id {d} not found", .{id});
    }
}

const ShaderInput = struct {
    texture_id: u32,
    vertex_data: []f32,
};

pub fn get_shader_pick_input(id: u32) !ShaderInput {
    // const asset = state.assets.get(id).?;
    if (state.assets.get(id)) |asset| {
        const vertex_data = try asset.get_vertex_pick_data();
        return ShaderInput{
            .texture_id = asset.texture_id,
            .vertex_data = vertex_data,
        };
    } else {
        unreachable("asset with id {d} not found", .{id});
    }
}

pub fn update_points(id: u32, points: [4]Types.PointUV) void {
    var asset_ptr: *Texture = state.assets.getPtr(id).?;
    asset_ptr.update_coords(points);
}

pub fn on_update_pick(id: u32) void {
    std.debug.print("on_update_pick: {d}\n", .{id});
    state.hovered_asset_id = id;
    // hovered element and asset ARE NOT THE SAME!!!!!
    // hovered element can be a control to rotate/change size of the asset
}

pub fn on_pointer_click() void {
    state.active_asset_id = state.hovered_asset_id;
}

pub fn on_pointer_down(x: f32, y: f32) void {
    if (state.active_asset_id >= ASSET_ID_TRESHOLD and state.active_asset_id == state.hovered_asset_id) {
        state.ongoing_action = .move;
        state.last_pointer_coords = Types.Point{ .x = x, .y = y };
    }
}

pub fn on_pointer_up() void {
    state.ongoing_action = .none;
}

pub fn on_pointer_move(x: f32, y: f32) !void {
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
        .none => {},
    }
}

pub fn get_border() ![]f32 {
    var vertex_data = std.ArrayList(f32).init(std.heap.page_allocator);
    // TODO: free memory, defer list.deinit();
    const red = [_]f32{ 1.0, 0.0, 0.0, 1.0 };
    if (state.assets.get(state.hovered_asset_id)) |asset| {
        for (asset.points, 0..) |point, i| {
            const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];
            const new_verticies = Line.get_vertex_data(
                point,
                next_point,
                20.0,
                red,
            );
            // std.debug.print("new_verticies: {any}\n", .{new_verticies});
            try vertex_data.appendSlice(new_verticies);
        }
    }

    const green = [_]f32{ 0.0, 1.0, 0.0, 1.0 };
    if (state.assets.get(state.active_asset_id)) |asset| {
        for (asset.points, 0..) |point, i| {
            const next_point = if (i == 3) asset.points[0] else asset.points[i + 1];

            try vertex_data.appendSlice(Line.get_vertex_data(
                point,
                next_point,
                20.0,
                green,
            ));
        }
    }

    return vertex_data.items;
}
