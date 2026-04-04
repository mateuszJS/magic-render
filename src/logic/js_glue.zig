const std = @import("std");
const types = @import("types.zig");
const bounding_box = @import("shapes/bounding_box.zig");

pub var onAssetSelection: *const fn ([4]u32) void = undefined;
pub var onUpdateTool: *const fn (u16) void = undefined;
pub var createSdfTexture: *const fn () u32 = undefined;
pub var createDisposableComputeDepthTexture: *const fn (u32, u32) u32 = undefined;
pub var getCharData: *const fn (u32, u21) SerializedCharDetails = undefined;
pub var getKerning: *const fn (u32, u21, u21) f32 = undefined;

pub var createCacheTexture: *const fn () u32 = undefined;
pub var startCache: *const fn (u32, bounding_box.BoundingBox, f32, f32) void = undefined;
pub var endCache: *const fn () void = undefined;

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
