const Image = @import("images.zig").Image;
const Point = @import("types.zig").Point;
const lines = @import("lines.zig");
const PointUV = @import("types.zig").PointUV;
const std = @import("std");
const Matrix3x3 = @import("matrix.zig").Matrix3x3;
const triangles = @import("triangles.zig");
const shared = @import("shared.zig");
const consts = @import("consts.zig");
const UI = @import("ui.zig");
const AssetId = @import("asset_id.zig").AssetId;
const Asset = @import("types.zig").Asset;

const white = @Vector(4, u8){ 255, 255, 255, 255 };
const black = @Vector(4, u8){ 0, 0, 0, 255 };
const normalized = @Vector(4, f32){ 255, 255, 255, 255 };

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

// et - enhanced transform, can maintain center and aspect ratio if needed
// @param x - x coordinate
// @param y - y coordinate
// @param a - maintain aspect ratio
// @param c - maintain center or by bypass if equal false
// @returns ep - enhanced point
fn et(x: f32, y: f32, a: bool, c: bool) Point {
    // const s = if (@abs(x - 1) > @abs(y - 1)) x else y;
    const s = (x + y) * 0.5;
    const a_x = if (a) s else x;
    const a_y = if (a) s else y;
    return if (c) .{
        .x = 2.0 * a_x - 1.0,
        .y = 2.0 * a_y - 1.0,
    } else .{
        .x = a_x,
        .y = a_y,
    };
}

pub fn transformPoints(ui_component_id: u32, bounds: *[4]PointUV, raw_pointer: Point, constrained: bool, maintain_center: bool) void {
    var matrix = Matrix3x3.getMatrixFromRectangle(bounds.*);
    const p = matrix.inverse().get(raw_pointer);

    // pivot points
    const p_start: f32 = if (maintain_center) 0.5 else 0;
    const p_end: f32 = if (maintain_center) 0.5 else 1;
    const c = maintain_center;
    const a = constrained;

    switch (ui_component_id) {
        1 => { // Top left corner
            // ep - enhanced point
            const ep = et(1 - p.x, p.y, a, c);
            matrix.pivotScale(ep.x, ep.y, p_end, p_start);
        },
        2 => { // Top right corner
            const ep = et(p.x, p.y, a, c);
            matrix.pivotScale(ep.x, ep.y, p_start, p_start);
        },
        3 => { // Bottom right corner
            const ep = et(p.x, 1 - p.y, a, c);
            matrix.pivotScale(ep.x, ep.y, p_start, p_end);
        },
        4 => { // Bottom left corner
            const ep = et(1 - p.x, 1 - p.y, a, c);
            matrix.pivotScale(ep.x, ep.y, p_end, p_end);
        },
        5 => { // top
            const ep = et(p.y, p.y, a, c);
            matrix.pivotScale(if (a) ep.x else 1.0, ep.y, 0.5, p_start);
        },
        6 => { // right
            const ep = et(p.x, p.x, a, c);
            matrix.pivotScale(ep.x, if (a) ep.y else 1.0, p_start, 0.5);
        },
        7 => { // bottom
            const ep = et(1 - p.y, 1 - p.y, a, c);
            matrix.pivotScale(if (a) ep.x else 1.0, ep.y, 0.5, p_end);
        },
        8 => { // left
            const ep = et(1 - p.x, 1 - p.x, a, c);
            matrix.pivotScale(ep.x, if (a) ep.y else 1.0, p_end, 0.5);
        },
        9 => {
            // rotation

            const center = bounds[0].mid(bounds[2]);
            const asset_angle_y = bounds[0].angleTo(bounds[3]);
            const pointer_angle = center.angleTo(raw_pointer);
            var asset_new_angle = pointer_angle - asset_angle_y;

            if (constrained) {
                const step = std.math.pi / 12.0; // 15 degrees
                const snapped = @round(pointer_angle / step) * step;
                asset_new_angle = snapped - asset_angle_y;
            }

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

    for (bounds, consts.DEFAULT_BOUNDS) |*b, p_uv| {
        const t_p = matrix.get(p_uv);
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

fn getPointsOfLine(b: [4]PointUV, t_line: TransformLine) struct { Point, Point } {
    if (t_line.id <= 4) {
        // corners
        const length = b[t_line.start].distance(b[t_line.end]);
        const angle = b[t_line.start].angleTo(b[t_line.end]);
        const sanitized_length = @min(30.0 * shared.render_scale, length * 0.1);

        const p1 = Point{
            .x = b[t_line.start].x,
            .y = b[t_line.start].y,
        };
        const p2 = Point{
            .x = b[t_line.start].x + @cos(angle) * sanitized_length,
            .y = b[t_line.start].y + @sin(angle) * sanitized_length,
        };

        return .{ p1, p2 };
    } else if (t_line.id <= 8) {
        // straight lines
        const point = b[t_line.start].mid(b[t_line.end]);
        const length = b[t_line.start].distance(b[t_line.end]);
        const angle = b[t_line.start].angleTo(b[t_line.end]);
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
            .x = (b[0].x + b[2].x) * 0.5,
            .y = (b[0].y + b[2].y) * 0.5,
        };
        const asset_mid_bottom = Point{
            .x = (b[2].x + b[3].x) * 0.5,
            .y = (b[2].y + b[3].y) * 0.5,
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
    bounds: [4]PointUV,
    hovered_elem_id: u32,
) struct {
    triangles: [RENDER_TRIANGLE_INSTANCES]triangles.DrawInstance,
    icon_vertex_data: UI.DrawVertex,
} {
    var triangle_buffer: [RENDER_TRIANGLE_INSTANCES]triangles.DrawInstance = undefined;
    var icon_vertex_data: UI.DrawVertex = undefined;

    var i: usize = 0;
    for (resize_lines) |t_line| {
        const color = if (hovered_elem_id == t_line.id) white else black;

        const p1, const p2 = getPointsOfLine(bounds, t_line);
        var thickness: f32 = 4.0 * shared.render_scale;

        if (t_line.id == 9) {
            // rotation icon
            thickness = 20.0 * shared.render_scale;
            const icon_size = thickness - 5.0 * shared.render_scale;
            const icon_color = if (hovered_elem_id == t_line.id) black else white;

            icon_vertex_data = UI.DrawVertex{
                .position = p1,
                .max_size = icon_size,
                .icon = UI.IconType.Rotate,
                .color = @as(@Vector(4, f32), @floatFromInt(icon_color)) / normalized,
            };
        }

        const outer_line_width = thickness + 3.0 * shared.render_scale;
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

    return .{
        .triangles = triangle_buffer,
        .icon_vertex_data = icon_vertex_data,
    };
}

pub const PICK_TRIANGLE_INSTANCES = UI_VERTICES_COUNT_BORDER * 2;
pub fn getPickVertexData(buffer: *[PICK_TRIANGLE_INSTANCES]triangles.PickInstance, bounds: [4]PointUV) void {
    var i: usize = 0;
    for (resize_lines) |t_line| {
        const p1, const p2 = getPointsOfLine(bounds, t_line);
        const thickness: f32 = if (t_line.id == 9) 30.0 * shared.render_scale else 10.0 * shared.render_scale;

        lines.getPickVertexData(
            buffer[i..][0..2],
            p1,
            p2,
            thickness + 10.0 * shared.render_scale,
            thickness / 2.0,
            .{ t_line.id, 0, 0, 0 },
        );

        i += 2;
    }
}

const UI_PATH_STRONG_COLOR = [_]u8{ 90, 90, 255, 255 };
const UI_PATH_LIGHT_COLOR = [_]u8{ UI_PATH_STRONG_COLOR[0], UI_PATH_STRONG_COLOR[1], UI_PATH_STRONG_COLOR[2], 30 };

pub fn getBorderDrawVertex(asset: Asset, strong: bool) [8]triangles.DrawInstance {
    var buffer: [8]triangles.DrawInstance = undefined;
    const bounds = asset.getBounds();
    const color = if (strong) UI_PATH_STRONG_COLOR else UI_PATH_LIGHT_COLOR;

    for (bounds, 0..) |point, i| {
        const next_point = if (i == 3) bounds[0] else bounds[i + 1];
        lines.getDrawVertexData(
            buffer[(i * 2)..][0..2],
            point,
            next_point,
            3.0 * shared.render_scale,
            color,
            1.5 * shared.render_scale,
        );
    }

    return buffer;
}
