const std = @import("std");
const Types = @import("types.zig");
const PointUV = Types.PointUV;

const SHADER_TRIANGLE_INDICIES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const DrawVertex = [6]PointUV;
pub const PickVertex = extern struct { point: PointUV, id: u32 };

pub const Asset = struct {
    id: u32,
    points: [4]PointUV,
    texture_id: u32,

    pub fn new(id: u32, points: [4]PointUV, texture_id: u32) Asset {
        return Asset{
            .id = id,
            .points = points,
            .texture_id = texture_id,
        };
    }

    pub fn get_render_vertex_data(self: Asset, buffer: *DrawVertex) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICIES) |index| {
            buffer[i] = self.points[index];
            i += 1;
        }
    }

    pub fn get_pick_vertex_data(self: Asset, buffer: *[6]PickVertex) void {
        for (SHADER_TRIANGLE_INDICIES, 0..) |index, i| {
            buffer[i] = .{
                .point = self.points[index],
                .id = self.id,
            };
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
        };
    }
};

pub const SerializedAsset = struct {
    points: [4]PointUV,
    texture_id: u32,
    id: u32,
};
