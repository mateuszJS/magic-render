const Image = @import("images.zig").Image;
const Point = @import("types.zig").Point;
const Line = @import("line.zig");
const PointUV = @import("types.zig").PointUV;
const std = @import("std");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const Msdf = @import("msdf.zig");
const Triangle = @import("triangle.zig");

const white = [4]u8{ 255, 255, 255, 255 };
const black = [4]u8{ 0, 0, 0, 255 };

const TransformLine = struct {
    id: u32,
    start: usize,
    end: usize,
};

const UI_VERTICIES_COUNT_BORDER = 13;
const resize_lines = [UI_VERTICIES_COUNT_BORDER]TransformLine{
    // corners, clock wise
    .{ .id = 1, .start = 0, .end = 1 },
    .{ .id = 1, .start = 0, .end = 3 },
    .{ .id = 2, .start = 1, .end = 0 },
    .{ .id = 2, .start = 1, .end = 2 },
    .{ .id = 3, .start = 2, .end = 1 },
    .{ .id = 3, .start = 2, .end = 3 },
    .{ .id = 4, .start = 3, .end = 0 },
    .{ .id = 4, .start = 3, .end = 2 },
    // straight lines, clock wise
    .{ .id = 5, .start = 0, .end = 1 },
    .{ .id = 6, .start = 1, .end = 2 },
    .{ .id = 7, .start = 2, .end = 3 },
    .{ .id = 8, .start = 3, .end = 0 },
    //  rotation
    .{ .id = 9, .start = 0, .end = 0 },
};

pub fn is_transform_ui(id: u32) bool {
    return id >= 1 and id <= 9;
}

pub fn tranform_points(ui_component_id: u32, points: *[4]PointUV, raw_x: f32, raw_y: f32) void {
    const asset_angle_y = points[0].angle_to(points[3]) + std.math.pi / 2.0;
    // it's important we dont meausre horizontal one, because reflecting by X axis makes no change in horizontal angle
    // but should be 180 degree opposite
    const t_matrix = Matrix3x3.rotation(asset_angle_y); // transfor matrix
    const invert_t_matrix = t_matrix.inverse().?;
    const pointer = invert_t_matrix.transform_point(Point{
        .x = raw_x,
        .y = raw_y,
    });

    var un_rotated_points = [4]Point{
        invert_t_matrix.transform_point(points[0]),
        invert_t_matrix.transform_point(points[1]),
        invert_t_matrix.transform_point(points[2]),
        invert_t_matrix.transform_point(points[3]),
    };

    switch (ui_component_id) {
        1 => {
            // Top left corner
            un_rotated_points[0].x = pointer.x;
            un_rotated_points[0].y = pointer.y;
            un_rotated_points[1].y = pointer.y;
            un_rotated_points[3].x = pointer.x;
        },
        2 => {
            // Top right corner
            un_rotated_points[1].x = pointer.x;
            un_rotated_points[1].y = pointer.y;
            un_rotated_points[0].y = pointer.y;
            un_rotated_points[2].x = pointer.x;
        },
        3 => {
            // bottom right corner
            un_rotated_points[2].x = pointer.x;
            un_rotated_points[2].y = pointer.y;
            un_rotated_points[3].y = pointer.y;
            un_rotated_points[1].x = pointer.x;
        },
        4 => {
            // bottom left corner
            un_rotated_points[3].x = pointer.x;
            un_rotated_points[3].y = pointer.y;
            un_rotated_points[2].y = pointer.y;
            un_rotated_points[0].x = pointer.x;
        },
        5 => {
            // top
            un_rotated_points[0].y = pointer.y;
            un_rotated_points[1].y = pointer.y;
        },

        6 => {
            // right
            un_rotated_points[1].x = pointer.x;
            un_rotated_points[2].x = pointer.x;
        },

        7 => {
            // bottom
            un_rotated_points[2].y = pointer.y;
            un_rotated_points[3].y = pointer.y;
        },

        8 => {
            // left
            un_rotated_points[0].x = pointer.x;
            un_rotated_points[3].x = pointer.x;
        },
        9 => {
            // rotation
            const asset_center = points[0].mid(points[2]);
            const asset_new_angle = std.math.atan2(
                asset_center.y - raw_y,
                asset_center.x - raw_x,
            ) - std.math.pi / 2.0;

            for (points) |*point| {
                const current_angle = std.math.atan2(point.y - asset_center.y, point.x - asset_center.x);
                const default_angle = current_angle - asset_angle_y; // angle without any user rotation introduced
                const length = std.math.hypot(point.x - asset_center.x, point.y - asset_center.y);
                const new_angle = default_angle + asset_new_angle;

                point.x = asset_center.x + length * @cos(new_angle);
                point.y = asset_center.y + length * @sin(new_angle);
            }
        },
        else => unreachable,
    }

    if (ui_component_id != 9) {
        const p0 = t_matrix.transform_point(un_rotated_points[0]);
        const p1 = t_matrix.transform_point(un_rotated_points[1]);
        const p2 = t_matrix.transform_point(un_rotated_points[2]);
        const p3 = t_matrix.transform_point(un_rotated_points[3]);

        points[0].x = p0.x;
        points[0].y = p0.y;
        points[1].x = p1.x;
        points[1].y = p1.y;
        points[2].x = p2.x;
        points[2].y = p2.y;
        points[3].x = p3.x;
        points[3].y = p3.y;
    }
}

fn get_points_of_line(img: Image, t_line: TransformLine, render_scale: f32) struct { Point, Point } {
    const points = img.points;
    if (t_line.id <= 4) {
        // corners
        const length = points[t_line.start].distance(points[t_line.end]);
        const angle = points[t_line.start].angle_to(points[t_line.end]);
        const sanitized_length = @min(30.0 * render_scale, length * 0.1);

        const p1 = Point{
            .x = points[t_line.start].x,
            .y = points[t_line.start].y,
        };
        const p2 = Point{
            .x = points[t_line.start].x + @cos(angle) * sanitized_length,
            .y = points[t_line.start].y + @sin(angle) * sanitized_length,
        };

        return .{ p1, p2 };
    } else if (t_line.id <= 8) {
        // straight lines
        const point = points[t_line.start].mid(points[t_line.end]);
        const length = points[t_line.start].distance(points[t_line.end]);
        const angle = points[t_line.start].angle_to(points[t_line.end]);
        const sanitized_length = @min(30.0 * render_scale, length * 0.07);

        const p1 = Point{
            .x = point.x + @cos(angle) * sanitized_length,
            .y = point.y + @sin(angle) * sanitized_length,
        };
        const p2 = Point{
            .x = point.x - @cos(angle) * sanitized_length,
            .y = point.y - @sin(angle) * sanitized_length,
        };

        return .{ p1, p2 };
    } else if (t_line.id == 9) {
        const asset_center = Point{
            .x = (points[0].x + points[2].x) * 0.5,
            .y = (points[0].y + points[2].y) * 0.5,
        };
        const asset_mid_bottom = Point{
            .x = (points[2].x + points[3].x) * 0.5,
            .y = (points[2].y + points[3].y) * 0.5,
        };
        const angle = std.math.atan2(asset_mid_bottom.y - asset_center.y, asset_mid_bottom.x - asset_center.x);
        const p1 = Point{
            .x = asset_mid_bottom.x + @cos(angle) * 60.0 * render_scale,
            .y = asset_mid_bottom.y + @sin(angle) * 60.0 * render_scale,
        };
        const p2 = Point{
            .x = p1.x + @cos(angle + std.math.pi / 4.0) * 0.1, // 0.01 just to make it 45 degree
            .y = p1.y + @sin(angle + std.math.pi / 4.0) * 0.1,
        };
        return .{ p1, p2 };
    } else {
        unreachable;
    }
}

pub const RENDER_TRIANGLE_INSTANCES = UI_VERTICIES_COUNT_BORDER * 2 * 2; // two triangle per line, each line has front and back color

pub fn get_draw_vertex_data(
    triangle_buffer: *[RENDER_TRIANGLE_INSTANCES]Triangle.DrawInstance,
    msdf_vertex_data: *[2]Msdf.DrawInstance,
    img: Image,
    hovered_elem_id: u32,
    render_scale: f32,
) void {
    var i: usize = 0;
    for (resize_lines) |t_line| {
        const color = if (hovered_elem_id == t_line.id) white else black;

        const p1, const p2 = get_points_of_line(img, t_line, render_scale);
        var thickness: f32 = 10.0 * render_scale;

        if (t_line.id == 9) {
            // rotation icon
            thickness = 30.0 * render_scale;
            const icon_size = thickness - 5.0 * render_scale;
            const msdf_data = Msdf.get_draw_vertex_data(
                Msdf.IconId.rotate,
                p1.x - icon_size * 0.5 - 0.12 * render_scale,
                p1.y - icon_size * 0.5 + 0.75 * render_scale,
                icon_size,
                if (hovered_elem_id == t_line.id) black else white,
            );
            msdf_vertex_data.* = msdf_data;
        }

        const outer_line_width = thickness + 10.0 * render_scale;
        Line.get_draw_vertex_data(
            triangle_buffer[i..][0..2],
            p1,
            p2,
            outer_line_width,
            white,
            outer_line_width / 2.0,
        );
        Line.get_draw_vertex_data(
            triangle_buffer[(RENDER_TRIANGLE_INSTANCES / 2) + i ..][0..2],
            p1,
            p2,
            thickness,
            color,
            thickness / 2.0,
        );

        i += 2;
    }
}

pub const PICK_TRIANGLE_INSTANCES = UI_VERTICIES_COUNT_BORDER * 2;
pub fn get_pick_vertex_data(buffer: *[PICK_TRIANGLE_INSTANCES]Triangle.PickInstance, img: Image, render_scale: f32) void {
    var i: usize = 0;
    for (resize_lines) |t_line| {
        const p1, const p2 = get_points_of_line(img, t_line, render_scale);
        const thickness: f32 = if (t_line.id == 9) 30.0 * render_scale else 10.0 * render_scale;

        Line.get_pick_vertex_data(
            buffer[i..][0..2],
            p1,
            p2,
            thickness + 10.0 * render_scale,
            thickness / 2.0,
            t_line.id,
        );

        i += 2;
    }
}
