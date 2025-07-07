const std = @import("std");
const Point = @import("types.zig").Point;
const Utils = @import("utils.zig");

pub const LINE_NUM_VERTICIES: usize = 2 * (3 * 4 + 4 + 3);
// 2 triangles, 3 verticies per triangle, 4 per position + 4 for color(same for all verticies) + 3 round value(f32 per vertex)
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

        // const points = [3]Types.Point{
        //     Types.Point{ .x = 100.0, .y = 70.0 }, //
        //     Types.Point{ .x = 300.0, .y = 100.0 }, //
        //     Types.Point{ .x = 100.0, .y = 150.0 },
        // };
        // const p0_v = get_round_corner_vector(0, points, 10.0);
        // const p1_v = get_round_corner_vector(1, points, 30.0);
        // const p2_v = get_round_corner_vector(2, points, 20.0);

        // const shape_vertex_data = [_]f32{
        //     p0_v[0], p0_v[1], p0_v[2], p0_v[3],
        //     p1_v[0], p1_v[1], p1_v[2], p1_v[3],
        //     p2_v[0], p2_v[1], p2_v[2], p2_v[3],
        //     0.0,     1.0,     0.0,     1.0,
        //     p0_v[4], p1_v[4], p2_v[4], // rounded corner values for each of three positions
        // };
        // web_gpu_programs.draw_triangle(&shape_vertex_data);

        var i: usize = 0;
        for (points, 0..) |p, index| {
            // const base = i * 4 + (i % 3 | 0) * (4 + 3);

            buffer[i + 0] = p.x;
            buffer[i + 1] = p.y;
            buffer[i + 2] = 0.0; // rounded corner circle x-coordinate
            buffer[i + 3] = 0.0; // rounded corner circle y-coordinate

            i += 4;

            if ((index + 1) % 3 == 0) {
                // color
                buffer[i + 0] = color[0];
                buffer[i + 1] = color[1];
                buffer[i + 2] = color[2];
                buffer[i + 3] = color[3];
                // round value
                buffer[i + 4] = 0.0;
                buffer[i + 5] = 0.0;
                buffer[i + 6] = 0.0;
                i += 7;
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

const NUM_OF_POINTS: usize = 4;
pub fn get_round_corner_vector(index: usize, points: [NUM_OF_POINTS]Point, radius: f32) [5]f32 {
    const p = points[index];
    const pa = points[(index + 1) % NUM_OF_POINTS];
    const pb = points[@min((index -% 1), (NUM_OF_POINTS - 1)) % NUM_OF_POINTS];

    const p_to_pa = p.angle_to(pa);
    const p_to_pb = p.angle_to(pb);
    const mid_angle_p0 = Utils.findMidAngle(p_to_pa, p_to_pb);

    const p0_diff_mid_to_neighbour_angle = Utils.angleDifference(mid_angle_p0, p_to_pa);
    const p0_circle_offset = radius / std.math.sin(p0_diff_mid_to_neighbour_angle);
    const p_circle = Point{
        .x = p.x + std.math.cos(mid_angle_p0) * p0_circle_offset,
        .y = p.y + std.math.sin(mid_angle_p0) * p0_circle_offset,
    };

    return [_]f32{ p.x, p.y, p_circle.x, p_circle.y, radius };
}
