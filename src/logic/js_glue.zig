const std = @import("std");
const types = @import("types.zig");

pub var create_sdf_texture: *const fn () u32 = undefined;
pub var create_compute_depth_texture: *const fn (u32, u32) u32 = undefined;
pub var getCharData: *const fn (u32, u21) SerializedCharDetails = undefined;
pub var getKerning: *const fn (u21, u21) f32 = undefined;

pub fn connectCreateSdfTexture(
    create_sdf: *const fn () u32,
    create_compute_depth: *const fn (u32, u32) u32,
) void {
    create_sdf_texture = create_sdf;
    create_compute_depth_texture = create_compute_depth;
}

pub const SerializedCharDetails = struct {
    points: []const types.Point = &.{},
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    sdf_texture_id: ?u32,

    pub fn setPaths(self: *SerializedCharDetails, points: []const types.Point) !void {
        self.points =
            if (points.len > 0)
                try std.heap.page_allocator.dupe(types.Point, points)
            else
                &.{};
    }
};
