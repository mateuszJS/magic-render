const Image = @import("images.zig").Image;
const Point = @import("types.zig").Point;
const lines = @import("lines.zig");
const PointUV = @import("types.zig").PointUV;
const std = @import("std");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const Msdf = @import("msdf.zig");
const Triangle = @import("triangle.zig");
const shared = @import("shared.zig");
const DEFAULT_BOUNDS = @import("consts.zig").DEFAULT_BOUNDS;

const white = [4]u8{ 255, 255, 255, 255 };
const black = [4]u8{ 0, 0, 0, 255 };

const TransformLine = struct {
    id: u32,
    start: usize,
    end: usize,
};

const UI_VERTICES_COUNT_BORDER = 13;
const resize_lines = [UI_VERTICES_COUNT_BORDER]TransformLine{
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

pub fn isTransformUi(id: u32) bool {
    return id >= 1 and id <= 9;
}

pub fn transformPoints(ui_component_id: u32, bounds: *[4]PointUV, raw_pointer: Point) void {
    var matrix = Matrix3x3.getMatrixFromRectangle(bounds.*);
    const pointer = matrix.inverse().get(raw_pointer);

    switch (ui_component_id) {
        1 => matrix.pivotScale(1 - pointer.x, pointer.y, 1, 0), // Top left corner
        2 => matrix.pivotScale(pointer.x, pointer.y, 0, 0), // Top right corner
        3 => matrix.pivotScale(pointer.x, 1 - pointer.y, 0, 1), // bottom right corner
        4 => matrix.pivotScale(1 - pointer.x, 1 - pointer.y, 1, 1), // bottom left corner
        5 => matrix.pivotScale(1, pointer.y, 0, 0), // top
        6 => matrix.pivotScale(pointer.x, 1, 0, 0), // right
        7 => matrix.pivotScale(1, 1 - pointer.y, 0, 1), // bottom
        8 => matrix.pivotScale(1 - pointer.x, 1, 1, 0), // left
        9 => {
            // rotation
            const center = bounds[0].mid(bounds[2]);
            const asset_angle_y = bounds[0].angleTo(bounds[3]);
            var asset_new_angle = center.angleTo(raw_pointer) - asset_angle_y;

            if (matrix.isMirrored()) {
                asset_new_angle *= -1;
            }

            matrix.translate(0.5, 0.5);
            const aspect = bounds[0].distance(bounds[1]) / bounds[0].distance(bounds[3]);
            matrix.rotateScaled(asset_new_angle, aspect);
            matrix.translate(-0.5, -0.5);
        },
        else => unreachable,
    }

    // angles has to be captured before transformation
    // just in case we will flatten one of the dimensions, then all the angles will point in one of two directions
    // and will NOT produce 1x1 bounds, but more like 1x0 or 0x1
    const angle_x = bounds[0].angleTo(bounds[1]);
    const angle_y = bounds[0].angleTo(bounds[3]);

    for (bounds, DEFAULT_BOUNDS) |*b, p| {
        const t_p = matrix.get(p);
        b.x = t_p.x;
        b.y = t_p.y;
    }

    if (bounds[0].distance(bounds[1]) < 1.0) {
        bounds[1].x = bounds[0].x + @cos(angle_x);
        bounds[1].y = bounds[0].y + @sin(angle_x);
        bounds[2].x = bounds[3].x + @cos(angle_x);
        bounds[2].y = bounds[3].y + @sin(angle_x);
    }

    if (bounds[0].distance(bounds[3]) < 1.0) {
        bounds[3].x = bounds[0].x + @cos(angle_y);
        bounds[3].y = bounds[0].y + @sin(angle_y);
        bounds[2].x = bounds[1].x + @cos(angle_y);
        bounds[2].y = bounds[1].y + @sin(angle_y);
    }
}

fn getPointsOfLine(points: [4]PointUV, t_line: TransformLine) struct { Point, Point } {
    if (t_line.id <= 4) {
        // corners
        const length = points[t_line.start].distance(points[t_line.end]);
        const angle = points[t_line.start].angleTo(points[t_line.end]);
        const sanitized_length = @min(30.0 * shared.render_scale, length * 0.1);

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
        const angle = points[t_line.start].angleTo(points[t_line.end]);
        const sanitized_length = @min(30.0 * shared.render_scale, length * 0.07);

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
            .x = asset_mid_bottom.x + @cos(angle) * 60.0 * shared.render_scale,
            .y = asset_mid_bottom.y + @sin(angle) * 60.0 * shared.render_scale,
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

pub const RENDER_TRIANGLE_INSTANCES = UI_VERTICES_COUNT_BORDER * 2 * 2; // two triangle per line, each line has front and back color

pub fn getDrawVertexData(
    triangle_buffer: *[RENDER_TRIANGLE_INSTANCES]Triangle.DrawInstance,
    msdf_vertex_data: *[2]Msdf.DrawInstance,
    points: [4]PointUV,
    hovered_elem_id: u32,
) void {
    var i: usize = 0;
    for (resize_lines) |t_line| {
        const color = if (hovered_elem_id == t_line.id) white else black;

        const p1, const p2 = getPointsOfLine(points, t_line);
        var thickness: f32 = 10.0 * shared.render_scale;

        if (t_line.id == 9) {
            // rotation icon
            thickness = 30.0 * shared.render_scale;
            const icon_size = thickness - 5.0 * shared.render_scale;
            const msdf_data = Msdf.getDrawVertexData(
                Msdf.IconId.rotate,
                p1.x - icon_size * 0.5 - 0.12 * shared.render_scale,
                p1.y - icon_size * 0.5 + 0.75 * shared.render_scale,
                icon_size,
                if (hovered_elem_id == t_line.id) black else white,
            );
            msdf_vertex_data.* = msdf_data;
        }

        const outer_line_width = thickness + 10.0 * shared.render_scale;
        lines.getDrawVertexData(
            triangle_buffer[i..][0..2],
            p1,
            p2,
            outer_line_width,
            white,
            outer_line_width / 2.0,
        );
        lines.getDrawVertexData(
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

pub const PICK_TRIANGLE_INSTANCES = UI_VERTICES_COUNT_BORDER * 2;
pub fn getPickVertexData(buffer: *[PICK_TRIANGLE_INSTANCES]Triangle.PickInstance, points: [4]PointUV) void {
    var i: usize = 0;
    for (resize_lines) |t_line| {
        const p1, const p2 = getPointsOfLine(points, t_line);
        const thickness: f32 = if (t_line.id == 9) 30.0 * shared.render_scale else 10.0 * shared.render_scale;

        lines.getPickVertexData(
            buffer[i..][0..2],
            p1,
            p2,
            thickness + 10.0 * shared.render_scale,
            thickness / 2.0,
            t_line.id,
        );

        i += 2;
    }
}
