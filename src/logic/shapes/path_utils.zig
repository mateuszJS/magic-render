const Point = @import("../types.zig").Point;

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
