const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const Utils = @import("utils.zig");
const math = @import("std").math;
const std = @import("std");
const triangles = @import("triangles.zig");

pub fn getDrawVertexData(buffer: *[2]triangles.DrawInstance, x: f32, y: f32, width: f32, height: f32, radius: f32, color: [4]u8) void {
    const points = [_]Point{
        .{ .x = x, .y = y }, //
        .{ .x = x + width, .y = y }, //
        .{ .x = x + width, .y = y + height }, //
        .{ .x = x, .y = y + height }, //
    };
    const p0_v = triangles.getRoundCornerVector(0, points, radius);
    const p1_v = triangles.getRoundCornerVector(1, points, radius);
    const p2_v = triangles.getRoundCornerVector(2, points, radius);
    const p3_v = triangles.getRoundCornerVector(3, points, radius);

    triangles.getDrawVertexData(buffer[0..1], p0_v, p1_v, p2_v, color);
    triangles.getDrawVertexData(buffer[1..2], p0_v, p2_v, p3_v, color);
}
pub fn getPickVertexData(buffer: *[2]triangles.PickInstance, x: f32, y: f32, width: f32, height: f32, radius: f32, id: u32) void {
    const points = [_]Point{
        .{ .x = x, .y = y }, //
        .{ .x = x + width, .y = y }, //
        .{ .x = x + width, .y = y + height }, //
        .{ .x = x, .y = y + height }, //
    };
    const p0_v = triangles.getRoundCornerVector(0, points, radius);
    const p1_v = triangles.getRoundCornerVector(1, points, radius);
    const p2_v = triangles.getRoundCornerVector(2, points, radius);
    const p3_v = triangles.getRoundCornerVector(3, points, radius);

    triangles.getPickVertexData(buffer[0..1], p0_v, p1_v, p2_v, id);
    triangles.getPickVertexData(buffer[1..2], p0_v, p2_v, p3_v, id);
}
