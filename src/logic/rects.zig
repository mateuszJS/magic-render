const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const math = @import("std").math;
const std = @import("std");
const triangles = @import("triangles.zig");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;

pub fn getDrawVertexData(buffer: *[2]triangles.DrawInstance, matrix: ?Matrix3x3, x: f32, y: f32, width: f32, height: f32, radius: f32, color: [4]u8) void {
    var points = [_]Point{
        .{ .x = x, .y = y }, //
        .{ .x = x + width, .y = y }, //
        .{ .x = x + width, .y = y + height }, //
        .{ .x = x, .y = y + height }, //
    };

    if (matrix) |m| {
        for (&points) |*p| {
            const new_pos = m.get(p);
            p.x = new_pos.x;
            p.y = new_pos.y;
        }
    }

    const p0_v = triangles.getRoundCornerVector(0, points, radius);
    const p1_v = triangles.getRoundCornerVector(1, points, radius);
    const p2_v = triangles.getRoundCornerVector(2, points, radius);
    const p3_v = triangles.getRoundCornerVector(3, points, radius);

    triangles.getDrawVertexData(buffer[0..1], p0_v, p1_v, p2_v, color);
    triangles.getDrawVertexData(buffer[1..2], p0_v, p2_v, p3_v, color);
}
pub fn getPickVertexData(matrix: ?Matrix3x3, x: f32, y: f32, width: f32, height: f32, radius: f32, id: [4]u32) [2]triangles.PickInstance {
    var buffer: [2]triangles.PickInstance = undefined;
    var points = [_]Point{
        .{ .x = x, .y = y }, //
        .{ .x = x + width, .y = y }, //
        .{ .x = x + width, .y = y + height }, //
        .{ .x = x, .y = y + height }, //
    };

    if (matrix) |m| {
        for (&points) |*p| {
            const new_pos = m.get(p);
            p.x = new_pos.x;
            p.y = new_pos.y;
        }
    }

    const p0_v = triangles.getRoundCornerVector(0, points, radius);
    const p1_v = triangles.getRoundCornerVector(1, points, radius);
    const p2_v = triangles.getRoundCornerVector(2, points, radius);
    const p3_v = triangles.getRoundCornerVector(3, points, radius);

    triangles.getPickVertexData(buffer[0..1], p0_v, p1_v, p2_v, id);
    triangles.getPickVertexData(buffer[1..2], p0_v, p2_v, p3_v, id);

    return buffer;
}
