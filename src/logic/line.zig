const std = @import("std");
const PointUV = @import("types.zig").PointUV;

pub const Line = struct {
    pub fn get_vertex_data(start: PointUV, end: PointUV, width: f32, color: [4]f32) []f32 {
        const vertex_data = std.heap.page_allocator.alloc(f32, 6 * 8) catch unreachable;

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

        // Fill the vertex data
        for (points, 0..) |p, i| {
            const base = i * 8;
            vertex_data[base + 0] = p.x;
            vertex_data[base + 1] = p.y;
            vertex_data[base + 2] = 0.0; // z-coordinate
            vertex_data[base + 3] = 1.0; // w-coordinate
            vertex_data[base + 4] = color[0];
            vertex_data[base + 5] = color[1];
            vertex_data[base + 6] = color[2];
            vertex_data[base + 7] = color[3];
        }

        return vertex_data;
    }
};
