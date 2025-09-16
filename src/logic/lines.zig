const std = @import("std");
const Point = @import("types.zig").Point;
const Utils = @import("utils.zig");
const triangles = @import("triangles.zig");

fn getPoints(start: anytype, end: anytype, width: f32, rounded: f32) [4]triangles.RoundCorner {
    const half_width = width / 2.0;
    const parallel_angle = std.math.atan2(end.y - start.y, end.x - start.x);
    const angle = parallel_angle + std.math.pi / 2.0; // perpendicular angle

    const ax = start.x - half_width * @cos(parallel_angle);
    const ay = start.y - half_width * @sin(parallel_angle);
    const bx = end.x + half_width * @cos(parallel_angle);
    const by = end.y + half_width * @sin(parallel_angle);

    const angle_cos = @cos(angle) * half_width;
    const angle_sin = @sin(angle) * half_width;
    const points = [_]Point{
        .{ .x = ax + angle_cos, .y = ay + angle_sin },
        .{ .x = ax - angle_cos, .y = ay - angle_sin },
        .{ .x = bx - angle_cos, .y = by - angle_sin },
        .{ .x = bx + angle_cos, .y = by + angle_sin },
    };

    return [_]triangles.RoundCorner{
        triangles.getRoundCornerVector(0, points, rounded),
        triangles.getRoundCornerVector(1, points, rounded),
        triangles.getRoundCornerVector(2, points, rounded),
        triangles.getRoundCornerVector(3, points, rounded),
    };
}

pub fn getDrawVertexData(buffer: *[2]triangles.DrawInstance, start: anytype, end: anytype, width: f32, color: [4]u8, rounded: f32) void {
    const points = getPoints(start, end, width, rounded);

    triangles.getDrawVertexData(buffer[0..1], points[0], points[1], points[2], color);
    triangles.getDrawVertexData(buffer[1..2], points[0], points[2], points[3], color);
}

pub fn getPickVertexData(buffer: *[2]triangles.PickInstance, start: anytype, end: anytype, width: f32, rounded: f32, id: u32) void {
    const points = getPoints(start, end, width, rounded);

    triangles.getPickVertexData(buffer[0..1], points[0], points[1], points[2], id);
    triangles.getPickVertexData(buffer[1..2], points[0], points[2], points[3], id);
}
