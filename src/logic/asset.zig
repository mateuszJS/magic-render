const std = @import("std");
const Types = @import("types.zig");
const PointUV = Types.PointUV;

const SHADER_TRIANGLE_INDICIES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const Asset = struct {
    id: u32,
    points: [4]PointUV,
    texture_id: u32,
    fill_color: [4]f32,
    stroke_color: [4]f32,
    stroke_width: f32,

    pub const VERTEX_BUFFER_SIZE: usize = 6 * 6; // 6 vertices, each with 6 attributes (x, y, z, w, u, v)
    pub const PICK_VERTEX_BUFFER_SIZE: usize = 7 * 6; // 6 vertices, each with 7 attributes (x, y, z, w, u, v, id)

    pub fn new(id: u32, points: [4]PointUV, texture_id: u32, fill_color: [4]f32, stroke_color: [4]f32, stroke_width: f32) Asset {
        return Asset{
            .id = id,
            .points = points,
            .texture_id = texture_id,
            .fill_color = fill_color,
            .stroke_color = stroke_color,
            .stroke_width = stroke_width,
        };
    }

    pub fn get_vertex_data(self: Asset, buffer: *[VERTEX_BUFFER_SIZE]f32) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICIES) |index| {
            const point = self.points[index];
            buffer[i * 6 + 0] = point.x;
            buffer[i * 6 + 1] = point.y;
            buffer[i * 6 + 2] = 0.0; // z-coordinate
            buffer[i * 6 + 3] = 1.0; // w-coordinate
            buffer[i * 6 + 4] = point.u; // u-coordinate
            buffer[i * 6 + 5] = point.v; // v-coordinate
            i += 1;
        }
    }

    pub fn get_vertex_pick_data(self: Asset, buffer: *[PICK_VERTEX_BUFFER_SIZE]f32) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICIES) |index| {
            const point = self.points[index];
            buffer[i * 7 + 0] = point.x;
            buffer[i * 7 + 1] = point.y;
            buffer[i * 7 + 2] = 0.0; // z-coordinate
            buffer[i * 7 + 3] = 1.0; // w-coordinate
            buffer[i * 7 + 4] = point.u; // u-coordinate
            buffer[i * 7 + 5] = point.v; // v-coordinate
            buffer[i * 7 + 6] = @floatFromInt(self.id); // v-coordinate
            i += 1;
        }
    }

    pub fn update_coords(self: *Asset, new_points: [4]Types.PointUV) void {
        for (&self.points, 0..) |*item, i| {
            item.* = new_points[i];
        }
    }

    pub fn serialize(self: Asset) SerializedAsset {
        return SerializedAsset{
            .points = self.points,
            .texture_id = self.texture_id,
            .id = self.id,
            .fill_color = self.fill_color,
            .stroke_color = self.stroke_color,
            .stroke_width = self.stroke_width,
        };
    }
};

pub const SerializedAsset = struct {
    points: [4]PointUV,
    texture_id: u32,
    id: u32,
    fill_color: [4]f32,
    stroke_color: [4]f32,
    stroke_width: f32,
};
