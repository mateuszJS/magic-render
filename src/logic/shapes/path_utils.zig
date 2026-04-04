const Point = @import("../types.zig").Point;
const triangles = @import("../triangles.zig");
const shared = @import("../shared.zig");
const rects = @import("../rects.zig");
const lines = @import("../lines.zig");
const std = @import("std");
const AssetId = @import("../asset_id.zig").AssetId;

const STRAIGHT_LINE_THRESHOLD = 1e+10;
pub const STRAIGHT_LINE_HANDLE = Point{
    .x = 1e+11,
    .y = 0.0,
};

pub fn prepareHalfStraightLines(curves: []Point) void {
    if (curves.len < 4) {
        return; // Not enough points to process
    }
    // Handle half straight lines to be treated as bezier curves
    for (curves, 0..) |point, i| {
        if (isStraightLineHandle(point)) {
            if (i % 4 == 1) { // first handle
                const second_handle = curves[i + 1];
                const is_full_straight_line = isStraightLineHandle(second_handle);
                if (!is_full_straight_line) {
                    curves[i] = curves[i - 1]; // assign to closest control point
                }
            } else if (i % 4 == 2) { // second handle
                const first_handle = curves[i - 1];
                const is_full_straight_line = isStraightLineHandle(first_handle);
                if (!is_full_straight_line) {
                    curves[i] = curves[i + 1]; // assign to closest control point
                }
            }
        }
    }
}

pub fn isStraightLineHandle(point: Point) bool {
    return point.x > STRAIGHT_LINE_THRESHOLD;
}

pub fn getOppositeHandle(control_point: Point, handle: Point) Point {
    if (isStraightLineHandle(handle)) {
        return STRAIGHT_LINE_HANDLE;
    }
    const diff = control_point.diff(handle);
    const opposite_point = Point{
        .x = control_point.x + diff.x,
        .y = control_point.y + diff.y,
    };

    return opposite_point;
}

const SKELETON_POINT_SIZE = 10.0;
const PICK_POINT_SCALE = 3.0;
pub const SKELETON_LINE_WIDTH: f32 = 2.0;

pub fn getVertexDrawSkeletonPoint(
    is_control_point: bool,
    point: Point,
    is_hovered: bool,
) [2]triangles.DrawInstance {
    var buffer: [2]triangles.DrawInstance = undefined;
    const color = if (is_hovered) [_]u8{ 0, 255, 0, 255 } else [_]u8{ 0, 0, 255, 255 };
    const size = SKELETON_POINT_SIZE * shared.ui_scale;
    const radius = if (is_control_point) 0.0 else size / 2.0;

    rects.getDrawVertexData(
        buffer[0..2],
        null,
        point.x - size / 2.0,
        point.y - size / 2.0,
        size,
        size,
        radius,
        color,
    );

    return buffer;
}

pub fn getVertexPickSkeletonPoint(
    is_control_point: bool,
    point: Point,
    id: [4]u32,
) [2]triangles.PickInstance {
    const size = SKELETON_POINT_SIZE * PICK_POINT_SCALE * shared.ui_scale;
    const radius = if (is_control_point) 0.0 else size / 2.0;

    return rects.getPickVertexData(
        null,
        point.x - size / 2.0,
        point.y - size / 2.0,
        size,
        size,
        radius,
        id,
    );
}

// draw control point and handles around
pub fn drawControlPoint(
    i: usize,
    len: usize,
    cp: Point,
    handles: [2]?Point,
    buffer: *std.ArrayList(triangles.DrawInstance),
    hover_id: ?AssetId,
) !void {
    for (handles, 0..) |option_hp, index| {
        if (option_hp) |hp| {
            if (isStraightLineHandle(hp)) continue;

            var local_buffer: [2]triangles.DrawInstance = undefined;
            lines.getDrawVertexData(
                local_buffer[0..2],
                cp,
                hp,
                SKELETON_LINE_WIDTH * shared.ui_scale,
                [_]u8{ 0, 0, 255, 255 },
                0.0,
            );
            try buffer.appendSlice(&local_buffer);

            const point_id: u32 = if (index == 0) @min(i -% 1, len - 1) else i + 1;
            const is_hovered = if (hover_id) |id| id.getTert() == point_id else false;
            try buffer.appendSlice(&getVertexDrawSkeletonPoint(
                false,
                hp,
                is_hovered,
            ));
        }
    }

    try buffer.appendSlice(&getVertexDrawSkeletonPoint(
        true,
        cp,
        if (hover_id) |id| id.getTert() == i else false,
    ));
}
