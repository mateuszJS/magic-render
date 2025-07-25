const std = @import("std");
const Point = @import("types.zig").Point;
const Utils = @import("utils.zig");
const Triangle = @import("triangle.zig");

fn get_points(start: anytype, end: anytype, width: f32, rounded: f32) [4]Triangle.RoundCorner {
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

    return [_]Triangle.RoundCorner{
        Triangle.get_round_corner_vector(0, points, rounded),
        Triangle.get_round_corner_vector(1, points, rounded),
        Triangle.get_round_corner_vector(2, points, rounded),
        Triangle.get_round_corner_vector(3, points, rounded),
    };
}

pub fn get_draw_vertex_data(buffer: *[2]Triangle.DrawInstance, start: anytype, end: anytype, width: f32, color: [4]u8, rounded: f32) void {
    const points = get_points(start, end, width, rounded);

    Triangle.get_draw_vertex_data(buffer[0..1], points[0], points[1], points[2], color);
    Triangle.get_draw_vertex_data(buffer[1..2], points[0], points[2], points[3], color);
}

pub fn get_pick_vertex_data(buffer: *[2]Triangle.PickInstance, start: anytype, end: anytype, width: f32, rounded: f32, id: u32) void {
    const points = get_points(start, end, width, rounded);

    Triangle.get_pick_vertex_data(buffer[0..1], points[0], points[1], points[2], id);
    Triangle.get_pick_vertex_data(buffer[1..2], points[0], points[2], points[3], id);
}
