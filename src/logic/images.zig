const std = @import("std");
const Types = @import("types.zig");
const PointUV = Types.PointUV;

const SHADER_TRIANGLE_INDICES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const DrawVertex = [6]PointUV;
pub const PickVertex = extern struct { point: PointUV, id: u32 };

pub const Image = struct {
    id: u32,
    points: [4]PointUV,
    texture_id: u32,

    pub fn new(id: u32, points: [4]PointUV, texture_id: u32) Image {
        return Image{
            .id = id,
            .points = points,
            .texture_id = texture_id,
        };
    }

    pub fn getRenderVertexData(self: Image, buffer: *DrawVertex) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICES) |index| {
            buffer[i] = self.points[index];
            i += 1;
        }
    }

    pub fn getPickVertexData(self: Image, buffer: *[6]PickVertex) void {
        for (SHADER_TRIANGLE_INDICES, 0..) |index, i| {
            buffer[i] = .{
                .point = self.points[index],
                .id = self.id,
            };
        }
    }

    pub fn serialize(self: Image) Serialized {
        return Serialized{
            .points = self.points,
            .texture_id = self.texture_id,
            .id = self.id,
        };
    }
};

pub const Serialized = struct {
    points: [4]PointUV,
    texture_id: u32,
    id: u32,
};
