const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const Utils = @import("utils.zig");
const math = @import("std").math;
const std = @import("std");
const Triangles = @import("triangle.zig");

pub fn get_draw_vertex_data(buffer: *[2]Triangles.DrawInstance, x: f32, y: f32, width: f32, height: f32, radius: f32, color: [4]u8) void {
    const points = [_]Point{
        .{ .x = x, .y = y }, //
        .{ .x = x + width, .y = y }, //
        .{ .x = x + width, .y = y + height }, //
        .{ .x = x, .y = y + height }, //
    };
    const p0_v = Triangles.get_round_corner_vector(0, points, radius);
    const p1_v = Triangles.get_round_corner_vector(1, points, radius);
    const p2_v = Triangles.get_round_corner_vector(2, points, radius);
    const p3_v = Triangles.get_round_corner_vector(3, points, radius);

    Triangles.get_draw_vertex_data(buffer[0..1], p0_v, p1_v, p2_v, color);
    Triangles.get_draw_vertex_data(buffer[1..2], p0_v, p2_v, p3_v, color);
}
