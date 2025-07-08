const std = @import("std");
const Point = @import("types.zig").Point;
const Utils = @import("utils.zig");
const Triangle = @import("triangle.zig");

pub const DRAW_VERTICIES_COUNT: usize = 2 * Triangle.DRAW_VERTICIES_COUNT;
pub const PICK_VERTICIES_COUNT: usize = 6 * 5;

pub fn get_vertex_data(buffer: *[DRAW_VERTICIES_COUNT]f32, start: anytype, end: anytype, width: f32, color: [4]f32, rounded: f32) void {
    const half_width = width / 2.0;
    const parallel_angle = std.math.atan2(end.y - start.y, end.x - start.x);
    const angle = parallel_angle + std.math.pi / 2.0; // perpendicular angle

    const ax = start.x - half_width * @cos(parallel_angle);
    const ay = start.y - half_width * @sin(parallel_angle);
    const bx = end.x + half_width * @cos(parallel_angle);
    const by = end.y + half_width * @sin(parallel_angle);

    const points = [_]Point{
        .{ .x = ax + half_width * @cos(angle), .y = ay + half_width * @sin(angle) },
        .{ .x = ax - half_width * @cos(angle), .y = ay - half_width * @sin(angle) },
        .{ .x = bx - half_width * @cos(angle), .y = by - half_width * @sin(angle) },
        .{ .x = bx + half_width * @cos(angle), .y = by + half_width * @sin(angle) },
    };

    const p0_v = Triangle.get_round_corner_vector(0, points, rounded);
    const p1_v = Triangle.get_round_corner_vector(1, points, rounded);
    const p2_v = Triangle.get_round_corner_vector(2, points, rounded);
    const p3_v = Triangle.get_round_corner_vector(3, points, rounded);

    Triangle.get_vertex_data(buffer[0..Triangle.DRAW_VERTICIES_COUNT], p0_v, p1_v, p2_v, color);
    Triangle.get_vertex_data(buffer[Triangle.DRAW_VERTICIES_COUNT .. 2 * Triangle.DRAW_VERTICIES_COUNT], p0_v, p2_v, p3_v, color);
}

pub fn get_vertex_data_pick(buffer: *[PICK_VERTICIES_COUNT]f32, start: anytype, end: anytype, width: f32, id: f32) void {
    const half_width = width / 2.0;
    const parallel_angle = std.math.atan2(end.y - start.y, end.x - start.x);
    const angle = parallel_angle + std.math.pi / 2.0; // perpendicular angle

    const ax = start.x - half_width * @cos(parallel_angle);
    const ay = start.y - half_width * @sin(parallel_angle);
    const bx = end.x + half_width * @cos(parallel_angle);
    const by = end.y + half_width * @sin(parallel_angle);

    // Create 6 vertices for two triangles forming a quad
    const points = [_]Point{
        .{ .x = ax - half_width * @cos(angle), .y = ay - half_width * @sin(angle) },
        .{ .x = ax + half_width * @cos(angle), .y = ay + half_width * @sin(angle) },
        .{ .x = bx + half_width * @cos(angle), .y = by + half_width * @sin(angle) },
        .{ .x = bx - half_width * @cos(angle), .y = by - half_width * @sin(angle) },
        .{ .x = ax - half_width * @cos(angle), .y = ay - half_width * @sin(angle) },
        .{ .x = bx + half_width * @cos(angle), .y = by + half_width * @sin(angle) },
    };

    // Fill the vertex data
    for (points, 0..) |p, i| {
        const base = i * 5;
        buffer[base + 0] = p.x;
        buffer[base + 1] = p.y;
        buffer[base + 2] = 0.0; // z-coordinate
        buffer[base + 3] = 1.0; // w-coordinate
        buffer[base + 4] = id;
    }
}
