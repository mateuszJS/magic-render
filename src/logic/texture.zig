const std = @import("std");
const Types = @import("types.zig");
const PointUV = Types.PointUV;

const SHADER_TRIANGLE_INDICIES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const AssetZig = struct {
    points: [4]PointUV,
    texture_id: u32,
};

pub const Texture = struct {
    id: u32,
    points: [4]PointUV,
    texture_id: u32,

    pub fn new(id: u32, points: [4]PointUV, texture_id: u32) Texture {
        return Texture{
            .id = id,
            .points = points,
            .texture_id = texture_id,
        };
    }

    pub fn get_vertex_data(self: Texture) []f32 {
        var vertex_data = std.heap.page_allocator.alloc(f32, 6 * 6) catch unreachable;
        // TODO: free memory
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICIES) |index| {
            const point = self.points[index];
            vertex_data[i * 6 + 0] = point.x;
            vertex_data[i * 6 + 1] = point.y;
            vertex_data[i * 6 + 2] = 0.0; // z-coordinate
            vertex_data[i * 6 + 3] = 1.0; // w-coordinate
            vertex_data[i * 6 + 4] = point.u; // u-coordinate
            vertex_data[i * 6 + 5] = point.v; // v-coordinate
            i += 1;
        }

        return vertex_data;
    }

    pub fn get_vertex_pick_data(self: Texture) []f32 {
        var vertex_data = std.heap.page_allocator.alloc(f32, 7 * 6) catch unreachable;
        // TODO: free memory
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICIES) |index| {
            const point = self.points[index];
            vertex_data[i * 7 + 0] = point.x;
            vertex_data[i * 7 + 1] = point.y;
            vertex_data[i * 7 + 2] = 0.0; // z-coordinate
            vertex_data[i * 7 + 3] = 1.0; // w-coordinate
            vertex_data[i * 7 + 4] = point.u; // u-coordinate
            vertex_data[i * 7 + 5] = point.v; // v-coordinate
            vertex_data[i * 7 + 6] = @floatFromInt(self.id); // v-coordinate
            i += 1;
        }

        return vertex_data;
    }

    pub fn update_coords(self: *Texture, new_points: [4]Types.PointUV) void {
        for (&self.points, 0..) |*item, i| {
            item.* = new_points[i];
        }
    }

    pub fn serialize(self: Texture) AssetZig {
        return AssetZig{
            .points = self.points,
            .texture_id = self.texture_id,
        };
    }
};
