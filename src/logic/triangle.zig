const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const Utils = @import("utils.zig");
const math = @import("std").math;
const std = @import("std");

pub const DrawInstance = extern struct {
    p0: PointUV,
    p1: PointUV,
    p2: PointUV,
    color: [4]u8,
    radius: [3]f32,
};

pub const PickInstance = extern struct {
    p0: PointUV,
    p1: PointUV,
    p2: PointUV,
    id: u32,
    radius: [3]f32,
};

pub fn get_draw_vertex_data(buffer: *[1]DrawInstance, p0: RoundCorner, p1: RoundCorner, p2: RoundCorner, color: [4]u8) void {
    buffer[0] = DrawInstance{
        .p0 = PointUV{
            .x = p0.corner.x,
            .y = p0.corner.y,
            .u = p0.circle.x,
            .v = p0.circle.y,
        },
        .p1 = PointUV{
            .x = p1.corner.x,
            .y = p1.corner.y,
            .u = p1.circle.x,
            .v = p1.circle.y,
        },
        .p2 = PointUV{
            .x = p2.corner.x,
            .y = p2.corner.y,
            .u = p2.circle.x,
            .v = p2.circle.y,
        },
        .color = color,
        // Radius list
        .radius = [_]f32{ p0.radius, p1.radius, p2.radius },
    };
}

pub fn get_pick_vertex_data(buffer: *[1]PickInstance, p0: RoundCorner, p1: RoundCorner, p2: RoundCorner, id: u32) void {
    buffer[0] = PickInstance{
        .p0 = PointUV{
            .x = p0.corner.x,
            .y = p0.corner.y,
            .u = p0.circle.x,
            .v = p0.circle.y,
        },
        .p1 = PointUV{
            .x = p1.corner.x,
            .y = p1.corner.y,
            .u = p1.circle.x,
            .v = p1.circle.y,
        },
        .p2 = PointUV{
            .x = p2.corner.x,
            .y = p2.corner.y,
            .u = p2.circle.x,
            .v = p2.circle.y,
        },
        .id = id,
        // Radius list
        .radius = [_]f32{ p0.radius, p1.radius, p2.radius },
    };
}

pub const RoundCorner = struct {
    corner: Point,
    circle: Point,
    radius: f32,
};

const NUM_OF_POINTS: usize = 4;
pub fn get_round_corner_vector(index: usize, points: [NUM_OF_POINTS]Point, radius: f32) RoundCorner {
    const p = points[index];
    const pa = points[(index + 1) % NUM_OF_POINTS];
    const pb = points[@min((index -% 1), (NUM_OF_POINTS - 1)) % NUM_OF_POINTS];

    const p_to_pa = p.angle_to(pa);
    const p_to_pb = p.angle_to(pb);
    const mid_angle_p = Utils.findMidAngle(p_to_pa, p_to_pb);

    const half_of_mid_angle_p = Utils.angleDifference(mid_angle_p, p_to_pa);
    const p0_circle_offset = radius / math.sin(half_of_mid_angle_p); // Pythagorean theorem
    const p_circle = Point{
        .x = p.x + math.cos(mid_angle_p) * p0_circle_offset,
        .y = p.y + math.sin(mid_angle_p) * p0_circle_offset,
    };

    return RoundCorner{
        .corner = p,
        .circle = p_circle,
        .radius = radius,
    };
}
