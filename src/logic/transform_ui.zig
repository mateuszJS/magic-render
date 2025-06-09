const Texture = @import("./texture.zig").Texture;
const Point = @import("types.zig").Point;
const LINE_NUM_VERTICIES = @import("./line.zig").LINE_NUM_VERTICIES;
const PICK_LINE_NUM_VERTICIES = @import("./line.zig").PICK_LINE_NUM_VERTICIES;
const Line = @import("./line.zig").Line;
const PointUV = @import("types.zig").PointUV;

const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
const black = [4]f32{ 0.0, 0.0, 0.0, 1.0 };

const TransformLine = struct {
    id: u32,
    relative_to_start_index: usize,
    relative_to_end_index: usize,
    offset_start: Point,
    offset_end: Point,
};

const UI_NUM_VERTICIES_BORDER = 12;
const resize_lines = [UI_NUM_VERTICIES_BORDER]TransformLine{
    // corners, clock wise
    .{ .id = 1, .relative_to_start_index = 0, .relative_to_end_index = 0, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 30.0, .y = 0.0 } },
    .{ .id = 1, .relative_to_start_index = 0, .relative_to_end_index = 0, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 0.0, .y = 30.0 } },
    .{ .id = 3, .relative_to_start_index = 1, .relative_to_end_index = 1, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = -30.0, .y = 0.0 } },
    .{ .id = 3, .relative_to_start_index = 1, .relative_to_end_index = 1, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 0.0, .y = 30.0 } },
    .{ .id = 5, .relative_to_start_index = 2, .relative_to_end_index = 2, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = -30.0, .y = 0.0 } },
    .{ .id = 5, .relative_to_start_index = 2, .relative_to_end_index = 2, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 0.0, .y = -30.0 } },
    .{ .id = 7, .relative_to_start_index = 3, .relative_to_end_index = 3, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 30.0, .y = 0.0 } },
    .{ .id = 7, .relative_to_start_index = 3, .relative_to_end_index = 3, .offset_start = Point{ .x = 0.0, .y = 0.0 }, .offset_end = Point{ .x = 0.0, .y = -30.0 } },
    // straight lines, clock wise
    .{ .id = 2, .relative_to_start_index = 0, .relative_to_end_index = 1, .offset_start = Point{ .x = -15.0, .y = 0.0 }, .offset_end = Point{ .x = 15.0, .y = 0.0 } },
    .{ .id = 4, .relative_to_start_index = 1, .relative_to_end_index = 2, .offset_start = Point{ .x = 0.0, .y = -15.0 }, .offset_end = Point{ .x = 0.0, .y = 15.0 } },
    .{ .id = 6, .relative_to_start_index = 2, .relative_to_end_index = 3, .offset_start = Point{ .x = -15.0, .y = 0.0 }, .offset_end = Point{ .x = 15.0, .y = 0.0 } },
    .{ .id = 8, .relative_to_start_index = 3, .relative_to_end_index = 0, .offset_start = Point{ .x = 0.0, .y = -15.0 }, .offset_end = Point{ .x = 0.0, .y = 15.0 } },
};

pub fn is_transform_ui(id: u32) bool {
    return id >= 1 and id <= 8;
}

pub fn tranform_points(ui_component_id: u32, points: *[4]PointUV, x: f32, y: f32) void {
    switch (ui_component_id) {
        1 => {
            // Top left corner
            points[0].x = x;
            points[0].y = y;
            points[1].y = y;
            points[3].x = x;
        },
        2 => {
            // top
            points[0].y = y;
            points[1].y = y;
        },
        3 => {
            // Top right corner
            points[1].x = x;
            points[1].y = y;
            points[0].y = y;
            points[2].x = x;
        },
        4 => {
            // right
            points[1].x = x;
            points[2].x = x;
        },
        5 => {
            // bottom right corner
            points[2].x = x;
            points[2].y = y;
            points[3].y = y;
            points[1].x = x;
        },
        6 => {
            // bottom
            points[2].y = y;
            points[3].y = y;
        },
        7 => {
            // bottom left corner
            points[3].x = x;
            points[3].y = y;
            points[2].y = y;
            points[0].x = x;
        },
        8 => {
            // left
            points[0].x = x;
            points[3].x = x;
        },
        else => unreachable,
    }
}

pub const BORDER_BUFFER_SIZE = UI_NUM_VERTICIES_BORDER * LINE_NUM_VERTICIES * 2;
const HALF_BUFFER = BORDER_BUFFER_SIZE / 2;

pub fn get_transform_ui(buffer: *[BORDER_BUFFER_SIZE]f32, texture: Texture, hovered_elem_id: u32) void {
    var i: usize = 0;
    for (resize_lines) |transform_line| {
        const relative_point = Point{
            .x = 0.5 * texture.points[transform_line.relative_to_start_index].x + 0.5 * texture.points[transform_line.relative_to_end_index].x,
            .y = 0.5 * texture.points[transform_line.relative_to_start_index].y + 0.5 * texture.points[transform_line.relative_to_end_index].y,
        };

        Line.get_vertex_data(
            buffer[i..][0..LINE_NUM_VERTICIES],
            Point{
                .x = relative_point.x + transform_line.offset_start.x,
                .y = relative_point.y + transform_line.offset_start.y,
            },
            Point{
                .x = relative_point.x + transform_line.offset_end.x,
                .y = relative_point.y + transform_line.offset_end.y,
            },
            20.0,
            white,
        );

        Line.get_vertex_data(
            buffer[(HALF_BUFFER + i)..][0..LINE_NUM_VERTICIES],
            Point{
                .x = relative_point.x + transform_line.offset_start.x,
                .y = relative_point.y + transform_line.offset_start.y,
            },
            Point{
                .x = relative_point.x + transform_line.offset_end.x,
                .y = relative_point.y + transform_line.offset_end.y,
            },
            10.0,
            if (hovered_elem_id == transform_line.id) white else black,
        );

        i += LINE_NUM_VERTICIES;
    }
}

pub const PICK_BORDER_BUFFER_SIZE = UI_NUM_VERTICIES_BORDER * PICK_LINE_NUM_VERTICIES;
pub fn get_transform_ui_pick(buffer: *[PICK_BORDER_BUFFER_SIZE]f32, texture: Texture) void {
    var i: usize = 0;
    for (resize_lines) |transform_line| {
        const relative_point = Point{
            .x = 0.5 * texture.points[transform_line.relative_to_start_index].x + 0.5 * texture.points[transform_line.relative_to_end_index].x,
            .y = 0.5 * texture.points[transform_line.relative_to_start_index].y + 0.5 * texture.points[transform_line.relative_to_end_index].y,
        };

        Line.get_vertex_data_pick(
            buffer[i..][0..PICK_LINE_NUM_VERTICIES],
            Point{
                .x = relative_point.x + transform_line.offset_start.x,
                .y = relative_point.y + transform_line.offset_start.y,
            },
            Point{
                .x = relative_point.x + transform_line.offset_end.x,
                .y = relative_point.y + transform_line.offset_end.y,
            },
            20.0,
            @floatFromInt(transform_line.id),
        );

        i += PICK_LINE_NUM_VERTICIES;
    }
}
