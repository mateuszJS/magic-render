const Point = @import("types.zig").Point;
const Utils = @import("utils.zig");
const math = @import("std").math;

pub const DRAW_VERTICIES_COUNT: usize = 3 * 4 + 4 + 3;
pub fn get_vertex_data(buffer: *[DRAW_VERTICIES_COUNT]f32, p0: [5]f32, p1: [5]f32, p2: [5]f32, color: [4]f32) void {
    buffer[0] = p0[0];
    buffer[1] = p0[1];
    buffer[2] = p0[2];
    buffer[3] = p0[3];
    buffer[4] = p1[0];
    buffer[5] = p1[1];
    buffer[6] = p1[2];
    buffer[7] = p1[3];
    buffer[8] = p2[0];
    buffer[9] = p2[1];
    buffer[10] = p2[2];
    buffer[11] = p2[3];
    buffer[12] = color[0];
    buffer[13] = color[1];
    buffer[14] = color[2];
    buffer[15] = color[3];
    buffer[16] = p0[4];
    buffer[17] = p1[4];
    buffer[18] = p2[4];
}

const NUM_OF_POINTS: usize = 4;
pub fn get_round_corner_vector(index: usize, points: [NUM_OF_POINTS]Point, radius: f32) [5]f32 {
    const p = points[index];
    const pa = points[(index + 1) % NUM_OF_POINTS];
    const pb = points[@min((index -% 1), (NUM_OF_POINTS - 1)) % NUM_OF_POINTS];

    const p_to_pa = p.angle_to(pa);
    const p_to_pb = p.angle_to(pb);
    const mid_angle_p0 = Utils.findMidAngle(p_to_pa, p_to_pb);

    const p0_diff_mid_to_neighbour_angle = Utils.angleDifference(mid_angle_p0, p_to_pa);
    const p0_circle_offset = radius / math.sin(p0_diff_mid_to_neighbour_angle);
    const p_circle = Point{
        .x = p.x + math.cos(mid_angle_p0) * p0_circle_offset,
        .y = p.y + math.sin(mid_angle_p0) * p0_circle_offset,
    };

    return [_]f32{ p.x, p.y, p_circle.x, p_circle.y, radius };
}
