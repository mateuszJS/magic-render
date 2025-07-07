const std = @import("std");
const Point = @import("types.zig").Point;

pub const LINE_NUM_VERTICIES: usize = 2 * (3 * 4 + 4);
// 2 triangles, 3 verticies per triangle, 4 per position + 4 for color(same for all verticies)
pub const PICK_LINE_NUM_VERTICIES: usize = 6 * 5;

pub const Line = struct {
    pub fn get_vertex_data(buffer: *[LINE_NUM_VERTICIES]f32, start: anytype, end: anytype, width: f32, color: [4]f32) void {
        const half_width = width / 2.0;
        const parallel_angle = std.math.atan2(end.y - start.y, end.x - start.x);
        const angle = parallel_angle + std.math.pi / 2.0; // perpendicular angle

        const ax = start.x - half_width * @cos(parallel_angle);
        const ay = start.y - half_width * @sin(parallel_angle);
        const bx = end.x + half_width * @cos(parallel_angle);
        const by = end.y + half_width * @sin(parallel_angle);

        // Create 6 vertices for two triangles forming a quad
        const points = [_]struct { x: f32, y: f32 }{
            .{ .x = ax - half_width * @cos(angle), .y = ay - half_width * @sin(angle) },
            .{ .x = ax + half_width * @cos(angle), .y = ay + half_width * @sin(angle) },
            .{ .x = bx + half_width * @cos(angle), .y = by + half_width * @sin(angle) },
            .{ .x = bx - half_width * @cos(angle), .y = by - half_width * @sin(angle) },
            .{ .x = ax - half_width * @cos(angle), .y = ay - half_width * @sin(angle) },
            .{ .x = bx + half_width * @cos(angle), .y = by + half_width * @sin(angle) },
        };

        var i: usize = 0;
        for (points) |p| {
            const base = i * 4 + (i % 3 | 0) * 4;
            buffer[base + 0] = p.x;
            buffer[base + 1] = p.y;
            buffer[base + 2] = 0.0; // z-coordinate
            buffer[base + 3] = 1.0; // w-coordinate

            i += 1;

            if (i % 3 == 0) {
                buffer[base + 4] = color[0];
                buffer[base + 5] = color[1];
                buffer[base + 6] = color[2];
                buffer[base + 7] = color[3];
            }
        }
    }
    pub fn get_vertex_data_pick(buffer: *[PICK_LINE_NUM_VERTICIES]f32, start: anytype, end: anytype, width: f32, id: f32) void {
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
};
