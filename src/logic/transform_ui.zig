const Texture = @import("./texture.zig").Texture;
const Point = @import("types.zig").Point;
const LINE_NUM_VERTICIES = @import("./line.zig").LINE_NUM_VERTICIES;
const PICK_LINE_NUM_VERTICIES = @import("./line.zig").PICK_LINE_NUM_VERTICIES;
const Line = @import("./line.zig").Line;
const PointUV = @import("types.zig").PointUV;
const std = @import("std");
const Matrix3x3 = @import("./matrix.zig").Matrix3x3;

const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
const black = [4]f32{ 0.0, 0.0, 0.0, 1.0 };

const TransformLine = struct {
    id: u32,
    relative_to_start_index: usize,
    relative_to_end_index: usize,
};

const UI_NUM_VERTICIES_BORDER = 13;
const resize_lines = [UI_NUM_VERTICIES_BORDER]TransformLine{
    // corners, clock wise
    .{ .id = 1, .relative_to_start_index = 0, .relative_to_end_index = 1 },
    .{ .id = 1, .relative_to_start_index = 0, .relative_to_end_index = 3 },
    .{ .id = 2, .relative_to_start_index = 1, .relative_to_end_index = 0 },
    .{ .id = 2, .relative_to_start_index = 1, .relative_to_end_index = 2 },
    .{ .id = 3, .relative_to_start_index = 2, .relative_to_end_index = 1 },
    .{ .id = 3, .relative_to_start_index = 2, .relative_to_end_index = 3 },
    .{ .id = 4, .relative_to_start_index = 3, .relative_to_end_index = 0 },
    .{ .id = 4, .relative_to_start_index = 3, .relative_to_end_index = 2 },
    // straight lines, clock wise
    .{ .id = 5, .relative_to_start_index = 0, .relative_to_end_index = 1 },
    .{ .id = 6, .relative_to_start_index = 1, .relative_to_end_index = 2 },
    .{ .id = 7, .relative_to_start_index = 2, .relative_to_end_index = 3 },
    .{ .id = 8, .relative_to_start_index = 3, .relative_to_end_index = 0 },
    //  rotation
    .{ .id = 9, .relative_to_start_index = 0, .relative_to_end_index = 0 },
};

pub fn is_transform_ui(id: u32) bool {
    return id >= 1 and id <= 9;
}

pub fn tranform_points(ui_component_id: u32, points: *[4]PointUV, raw_x: f32, raw_y: f32) void {
    const asset_angle = points[0].angle_to(points[1]);
    const transform_matrix = Matrix3x3.rotation(asset_angle);
    const inverted_transform_matrix = transform_matrix.inverse().?;
    const pointer = inverted_transform_matrix.transform_point(Point{
        .x = raw_x,
        .y = raw_y,
    });

    var un_rotated_points = [4]Point{
        inverted_transform_matrix.transform_point(points[0]),
        inverted_transform_matrix.transform_point(points[1]),
        inverted_transform_matrix.transform_point(points[2]),
        inverted_transform_matrix.transform_point(points[3]),
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
            const asset_pointer_angle = std.math.atan2(raw_y - asset_center.y, raw_x - asset_center.x);
            const asset_new_angle = asset_pointer_angle + std.math.pi / 2.0;

            for (points) |*point| {
                const current_angle = std.math.atan2(point.y - asset_center.y, point.x - asset_center.x);
                const default_angle = current_angle - asset_angle; // angle without any user rotation introduced
                const length = std.math.hypot(point.x - asset_center.x, point.y - asset_center.y);
                const new_angle = default_angle + asset_new_angle;

                point.x = asset_center.x + length * @cos(new_angle);
                point.y = asset_center.y + length * @sin(new_angle);
            }
        },
        else => unreachable,
    }

    if (ui_component_id != 9) {
        const p0 = transform_matrix.transform_point(un_rotated_points[0]);
        const p1 = transform_matrix.transform_point(un_rotated_points[1]);
        const p2 = transform_matrix.transform_point(un_rotated_points[2]);
        const p3 = transform_matrix.transform_point(un_rotated_points[3]);

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

fn get_points_of_line(texture: Texture, transform_line: TransformLine) struct { Point, Point } {
    if (transform_line.id <= 4) {
        // corners
        const length = texture.points[transform_line.relative_to_start_index].distance(texture.points[transform_line.relative_to_end_index]);
        const angle = texture.points[transform_line.relative_to_start_index].angle_to(texture.points[transform_line.relative_to_end_index]);
        const sanitized_length = @min(30.0, length * 0.1);

        const p1 = Point{
            .x = texture.points[transform_line.relative_to_start_index].x,
            .y = texture.points[transform_line.relative_to_start_index].y,
        };
        const p2 = Point{
            .x = texture.points[transform_line.relative_to_start_index].x + @cos(angle) * sanitized_length,
            .y = texture.points[transform_line.relative_to_start_index].y + @sin(angle) * sanitized_length,
        };

        return .{ p1, p2 };
    } else if (transform_line.id <= 8) {
        // straight lines
        const relative_point = texture.points[transform_line.relative_to_start_index].mid(texture.points[transform_line.relative_to_end_index]);
        const length = texture.points[transform_line.relative_to_start_index].distance(texture.points[transform_line.relative_to_end_index]);
        const angle = texture.points[transform_line.relative_to_start_index].angle_to(texture.points[transform_line.relative_to_end_index]);
        const sanitized_length = @min(30.0, length * 0.07);

        const p1 = Point{
            .x = relative_point.x + @cos(angle) * sanitized_length,
            .y = relative_point.y + @sin(angle) * sanitized_length,
        };
        const p2 = Point{
            .x = relative_point.x - @cos(angle) * sanitized_length,
            .y = relative_point.y - @sin(angle) * sanitized_length,
        };

        return .{ p1, p2 };
    } else if (transform_line.id == 9) {
        const asset_center = Point{
            .x = (texture.points[0].x + texture.points[2].x) * 0.5,
            .y = (texture.points[0].y + texture.points[2].y) * 0.5,
        };
        const asset_mid_bottom = Point{
            .x = (texture.points[2].x + texture.points[3].x) * 0.5,
            .y = (texture.points[2].y + texture.points[3].y) * 0.5,
        };
        const angle = std.math.atan2(asset_mid_bottom.y - asset_center.y, asset_mid_bottom.x - asset_center.x);
        const p1 = Point{
            .x = asset_mid_bottom.x + @cos(angle) * 60.0,
            .y = asset_mid_bottom.y + @sin(angle) * 60.0,
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

pub const BORDER_BUFFER_SIZE = UI_NUM_VERTICIES_BORDER * LINE_NUM_VERTICIES * 2;
const HALF_BUFFER = BORDER_BUFFER_SIZE / 2;

pub fn get_transform_ui(buffer: *[BORDER_BUFFER_SIZE]f32, texture: Texture, hovered_elem_id: u32) void {
    var i: usize = 0;
    for (resize_lines) |transform_line| {
        const p1, const p2 = get_points_of_line(texture, transform_line);
        const thickness: f32 = if (transform_line.id == 9) 30.0 else 10.0;

        Line.get_vertex_data(buffer[i..][0..LINE_NUM_VERTICIES], p1, p2, thickness + 10.0, white);
        Line.get_vertex_data(
            buffer[(HALF_BUFFER + i)..][0..LINE_NUM_VERTICIES],
            p1,
            p2,
            thickness,
            if (hovered_elem_id == transform_line.id) white else black,
        );
        // if (hovered_elem_id == transform_line.id) white else black,

        i += LINE_NUM_VERTICIES;
    }
}

pub const PICK_BORDER_BUFFER_SIZE = UI_NUM_VERTICIES_BORDER * PICK_LINE_NUM_VERTICIES;
pub fn get_transform_ui_pick(buffer: *[PICK_BORDER_BUFFER_SIZE]f32, texture: Texture) void {
    var i: usize = 0;
    for (resize_lines) |transform_line| {
        const p1, const p2 = get_points_of_line(texture, transform_line);
        const thickness: f32 = if (transform_line.id == 9) 30.0 else 10.0;

        Line.get_vertex_data_pick(buffer[i..][0..PICK_LINE_NUM_VERTICIES], p1, p2, thickness + 10.0, @floatFromInt(transform_line.id));

        i += PICK_LINE_NUM_VERTICIES;
    }
}
