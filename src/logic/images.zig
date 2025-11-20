const std = @import("std");
const Types = @import("types.zig");
const PointUV = Types.PointUV;
const utils = @import("utils.zig");

const SHADER_TRIANGLE_INDICES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const PickVertex = extern struct {
    point: PointUV,
    id: [4]u32,
};

pub const Image = struct {
    id: u32,
    bounds: [4]PointUV,
    texture_id: u32,

    pub fn new(id: u32, bounds: [4]PointUV, texture_id: u32) Image {
        return Image{
            .id = id,
            .bounds = bounds,
            .texture_id = texture_id,
        };
    }

    pub fn getRenderVertexData(self: Image, buffer: *[6]PointUV) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICES) |index| {
            buffer[i] = self.bounds[index];
            i += 1;
        }
    }

    pub fn getPickVertexData(self: Image, buffer: *[6]PickVertex) void {
        for (SHADER_TRIANGLE_INDICES, 0..) |index, i| {
            buffer[i] = .{ .point = self.bounds[index], .id = .{ self.id, 0, 0, 0 } };
        }
    }

    pub fn serialize(self: Image) Serialized {
        return Serialized{
            .bounds = self.bounds,
            .texture_id = self.texture_id,
            .id = self.id,
        };
    }
};

pub const Serialized = struct {
    bounds: [4]PointUV,
    texture_id: u32,
    id: u32,

    pub fn compare(self: Serialized, other: Serialized) bool {
        return self.id == other.id and
            self.texture_id == other.texture_id and
            utils.compareBounds(self.bounds, other.bounds);
    }
};
