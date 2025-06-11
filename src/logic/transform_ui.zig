const Texture = @import("./texture.zig").Texture;
const Point = @import("types.zig").Point;
const LINE_NUM_VERTICIES = @import("./line.zig").LINE_NUM_VERTICIES;
const PICK_LINE_NUM_VERTICIES = @import("./line.zig").PICK_LINE_NUM_VERTICIES;
const Line = @import("./line.zig").Line;
const PointUV = @import("types.zig").PointUV;
const std = @import("std");

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
    const asset_current_angle = points[0].angle_to(points[1]);

    const asset_center = points[0].mid(points[2]);
    const asset_pointer_angle = std.math.atan2(raw_y - asset_center.y, raw_x - asset_center.x);
    const pointer_center_distance: f32 = std.math.hypot(raw_x - asset_center.x, raw_y - asset_center.y);

    const x = asset_center.x + @cos(asset_pointer_angle - asset_current_angle) * pointer_center_distance;
    const y = asset_center.y + @sin(asset_pointer_angle - asset_current_angle) * pointer_center_distance;
    // const x = asset_center.x + @cos(asset_pointer_angle - asset_current_angle) * pointer_center_distance;
    // const y = asset_center.y + @sin(asset_pointer_angle - asset_current_angle) * pointer_center_distance;

    switch (ui_component_id) {
        1 => {
            // Top left corner

            const point0_angle = asset_center.angle_to(points[0]);
            const point0_distance: f32 = std.math.hypot(points[0].x - asset_center.x, points[0].y - asset_center.y);
            points[0].x = x + asset_center.x + @cos(point0_angle + asset_current_angle) * point0_distance;
            points[0].y = y + asset_center.x + @sin(point0_angle + asset_current_angle) * point0_distance;

            points[1].y = y;

            const point1_angle = asset_center.angle_to(points[0]);
            _ = point1_angle; // autofix
            const point1_distance: f32 = std.math.hypot(points[0].x - asset_center.x, points[0].y - asset_center.y);
            _ = point1_distance; // autofix
            points[0].x = asset_center.x + @cos(point0_angle + asset_current_angle) * point0_distance;
            points[0].y = asset_center.x + @sin(point0_angle + asset_current_angle) * point0_distance;

            points[3].x = x;
        },
        2 => {
            // Top right corner
            points[1].x = x;
            points[1].y = y;
            points[0].y = y;
            points[2].x = x;
        },
        3 => {
            // bottom right corner
            points[2].x = x;
            points[2].y = y;
            points[3].y = y;
            points[1].x = x;
        },
        4 => {
            // bottom left corner
            points[3].x = x;
            points[3].y = y;
            points[2].y = y;
            points[0].x = x;
        },
        5 => {
            // top
            points[0].y = y;
            points[1].y = y;
        },

        6 => {
            // right
            points[1].x = x;
            points[2].x = x;
        },

        7 => {
            // bottom
            points[2].y = y;
            points[3].y = y;
        },

        8 => {
            // left
            points[0].x = x;
            points[3].x = x;
        },
        9 => {
            // rotation
            const asset_new_angle = asset_pointer_angle + std.math.pi / 2.0;

            for (points, 0..) |*point, i| {
                _ = i; // autofix
                const current_angle = std.math.atan2(point.y - asset_center.y, point.x - asset_center.x);
                const default_angle = current_angle - asset_current_angle; // angle without any user rotation introduced
                const length = std.math.hypot(point.x - asset_center.x, point.y - asset_center.y);
                const new_angle = default_angle + asset_new_angle;

                // if (i == 0) {
                //     std.debug.print("raw_x :{}, raw_y: {}\n", .{ raw_x, raw_y }); // 388, 738
                //     std.debug.print("asset_center x:{}, y: {}\n", .{ asset_center.x, asset_center.y }); // 386.6, 373.5
                //     std.debug.print("asset_current_angle: {}\n", .{asset_current_angle}); // 0
                //     // const asset_pointer_angle = std.math.atan2(raw_y - asset_center.y, raw_x - asset_center.x);
                //     std.debug.print("asset_pointer_angle: {}\n", .{asset_pointer_angle}); // 1.56
                //     std.debug.print("point x:{}, y: {}\n", .{ point.x, point.y }); // 84.5, 71.5
                //     std.debug.print("current_angle: {}\n", .{current_angle}); //  -2.3561945
                //     std.debug.print("default_angle: {}\n", .{default_angle}); // -2.3561945
                //     std.debug.print("new_angle: {}\n", .{new_angle}); // 0.7812829
                // }

                point.x = asset_center.x + length * @cos(new_angle);
                point.y = asset_center.y + length * @sin(new_angle);
            }
        },
        else => unreachable,
    }
}

fn get_points_of_line(texture: Texture, transform_line: TransformLine) struct { Point, Point } {
    if (transform_line.id <= 4) {
        // corners
        const length_x = texture.points[transform_line.relative_to_end_index].x - texture.points[transform_line.relative_to_start_index].x;
        const length_y = texture.points[transform_line.relative_to_end_index].y - texture.points[transform_line.relative_to_start_index].y;
        const sign_x: f32 = if (length_x >= 0.0) 1.0 else -1.0;
        const sign_y: f32 = if (length_y >= 0.0) 1.0 else -1.0;
        const sanitized_length_x = sign_x * @min(30.0, @abs(length_x) * 0.1);
        const sanitized_length_y = sign_y * @min(30.0, @abs(length_y) * 0.1);

        const p1 = Point{
            .x = texture.points[transform_line.relative_to_start_index].x,
            .y = texture.points[transform_line.relative_to_start_index].y,
        };
        const p2 = Point{
            .x = texture.points[transform_line.relative_to_start_index].x + sanitized_length_x,
            .y = texture.points[transform_line.relative_to_start_index].y + sanitized_length_y,
        };

        return .{ p1, p2 };
    } else if (transform_line.id <= 8) {
        // straight lines
        const relative_point = Point{
            .x = 0.5 * (texture.points[transform_line.relative_to_start_index].x + texture.points[transform_line.relative_to_end_index].x),
            .y = 0.5 * (texture.points[transform_line.relative_to_start_index].y + texture.points[transform_line.relative_to_end_index].y),
        };
        const length_x = @abs(texture.points[transform_line.relative_to_end_index].x - texture.points[transform_line.relative_to_start_index].x);
        const length_y = @abs(texture.points[transform_line.relative_to_end_index].y - texture.points[transform_line.relative_to_start_index].y);
        const sanitiez_half_length_x = @min(30.0, length_x * 0.1) / 2.0;
        const sanitiez_half_length_y = @min(30.0, length_y * 0.1) / 2.0;

        const p1 = Point{
            .x = relative_point.x + sanitiez_half_length_x,
            .y = relative_point.y + sanitiez_half_length_y,
        };
        const p2 = Point{
            .x = relative_point.x - sanitiez_half_length_x,
            .y = relative_point.y - sanitiez_half_length_y,
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
