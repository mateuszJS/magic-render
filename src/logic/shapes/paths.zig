const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");
const shared = @import("../shared.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;

const STRAIGHT_LINE_THRESHOLD = 1e+10;
const STRAIGHT_LINE_HANDLE = Point{
    .x = 1e+11,
    .y = 0.0,
};

fn getOppositeHandle(control_point: Point, handle: Point) Point {
    if (Path.isStraightLineHandle(handle)) {
        return STRAIGHT_LINE_HANDLE;
    }
    const diff = control_point.diff(handle);
    const opposite_point = Point{
        .x = control_point.x + diff.x,
        .y = control_point.y + diff.y,
    };

    return opposite_point;
}

pub const Path = struct {
    points: std.ArrayList(Point),
    closed: bool, // Whether the shape is closed

    pub fn isStraightLineHandle(point: Point) bool {
        return point.x > STRAIGHT_LINE_THRESHOLD;
    }

    pub fn new(point: Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.append(point);
        try point_list.append(STRAIGHT_LINE_HANDLE);

        const shape = Path{
            .points = point_list,
            .closed = false,
        };

        return shape;
    }

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice
    pub fn newFromPoints(path: []const Point, same_point_threshold: f32, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        var closed = false;

        for (path, 0..) |point, i| {
            try point_list.append(point);

            if (i == path.len - 1) {
                const distance = path[0].distance(point);
                if (distance < same_point_threshold) {
                    // here is the problem, it should be overlap with exactly one point, then it might be caunted a closed
                    // althouhg the better word might be that a curve is open. More than one curve in a shape might be open!
                    closed = true;
                    std.debug.print("Path.newFromPoints - set to closed\n", .{});
                }
            }
        }

        return Path{
            .points = point_list,
            .closed = closed,
        };
    }

    pub fn addPoint(self: *Path, point: Point, same_point_threshold: Point) !void {
        if (self.closed) {
            @panic("Attempting to add point to already closed path!");
        }

        if (self.points.items.len > 2) {
            // The drop shape should be possible, but it's not right now
            const last_cp = self.points.getLast().clone();
            const last_handle = self.points.items[self.points.items.len - 2].clone();
            try self.points.append(last_cp);
            try self.points.append(getOppositeHandle(last_cp, last_handle));
        }

        try self.points.append(STRAIGHT_LINE_HANDLE);

        const first_point = self.points.items[0];

        if (@abs(first_point.x - point.x) < same_point_threshold.x and @abs(first_point.y - point.y) < same_point_threshold.y) {
            self.closed = true;
            try self.points.append(first_point);
        } else {
            try self.points.append(point);
        }
    }

    pub fn getSkeletonDrawVertexData(
        self: Path,
        matrix: Matrix3x3,
        allocator: std.mem.Allocator,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const size = 20.0 * shared.render_scale;

        for (self.points.items, 0..) |relative_point, i| {
            if (Path.isStraightLineHandle(relative_point)) {
                // This is a straight line handle, skip it
                continue;
            }

            const point = matrix.get(relative_point);

            const is_control_point = i % 4 == 0 or i % 4 == 3;
            if (!is_control_point) {
                const connected_control_point_index = if (i % 4 == 1) i - 1 else (i + 1) % self.points.items.len;
                const connected_control_point = matrix.get(self.points.items[connected_control_point_index]);
                var buffer: [2]triangles.DrawInstance = undefined;
                lines.getDrawVertexData(
                    buffer[0..2],
                    connected_control_point,
                    point,
                    3.0 * shared.render_scale,
                    [_]u8{ 0, 0, 255, 255 },
                    0.0,
                );
                try skeleton_buffer.appendSlice(&buffer);
            }

            var buffer: [2]triangles.DrawInstance = undefined;
            squares.getDrawVertexData(
                buffer[0..2],
                point.x - size / 2.0,
                point.y - size / 2.0,
                size,
                size,
                0.0,
                [_]u8{ 0, 0, 255, 255 },
            );
            try skeleton_buffer.appendSlice(&buffer);
        }

        const last_handle_norm = self.points.items[self.points.items.len - 2];
        if (!self.closed and self.points.items.len != 2 and !Path.isStraightLineHandle(last_handle_norm)) {
            const last_handle = matrix.get(last_handle_norm);
            const last_cp = matrix.get(self.points.getLast());
            const forward_handle = getOppositeHandle(last_cp, last_handle);
            var line_buffer: [2]triangles.DrawInstance = undefined;
            lines.getDrawVertexData(
                line_buffer[0..2],
                last_cp,
                forward_handle,
                3.0 * shared.render_scale,
                [_]u8{ 0, 0, 255, 255 },
                0.0,
            );
            try skeleton_buffer.appendSlice(&line_buffer);

            var square_buffer: [2]triangles.DrawInstance = undefined;
            squares.getDrawVertexData(
                square_buffer[0..2],
                forward_handle.x - size / 2.0,
                forward_handle.y - size / 2.0,
                size,
                size,
                0.0,
                [_]u8{ 0, 0, 255, 255 },
            );
            try skeleton_buffer.appendSlice(&square_buffer);
        }

        return skeleton_buffer.toOwnedSlice();
    }

    fn getClosedPathPoints(self: Path, allocator: std.mem.Allocator, preview_point: ?Point) !?[]Point {
        if (self.points.items.len <= 2 and preview_point == null) {
            return null;
        }

        var curves_list = std.ArrayList(Point).init(allocator);

        // Copy points manually
        for (self.points.items) |point| {
            try curves_list.append(point);
        }

        if (!self.closed) {
            if (preview_point) |preview| {
                if (self.points.items.len > 2) {
                    const last_cp = self.points.getLast().clone();
                    const last_handle = self.points.items[self.points.items.len - 2].clone();
                    try curves_list.append(last_cp);
                    try curves_list.append(getOppositeHandle(last_cp, last_handle));
                }

                try curves_list.append(STRAIGHT_LINE_HANDLE);
                try curves_list.append(preview);
            }

            const last_curve_point = curves_list.getLast().clone();
            const first_curve_point = curves_list.items[0].clone();
            try curves_list.append(last_curve_point);
            try curves_list.append(STRAIGHT_LINE_HANDLE);
            try curves_list.append(STRAIGHT_LINE_HANDLE);
            try curves_list.append(first_curve_point);
        }

        return try curves_list.toOwnedSlice();
    }

    fn prepareHalfStraightLines(curves: []Point) void {
        if (curves.len < 4) {
            return; // Not enough points to process
        }
        // Handle half straight lines to be treated as bezier curves
        for (curves, 0..) |point, i| {
            if (Path.isStraightLineHandle(point)) {
                if (i % 4 == 1) { // first handle
                    const second_handle = curves[i + 1];
                    const is_full_straight_line = Path.isStraightLineHandle(second_handle);
                    if (!is_full_straight_line) {
                        curves[i] = curves[i - 1]; // assign to closest control point
                    }
                } else if (i % 4 == 2) { // second handle
                    const first_handle = curves[i - 1];
                    const is_full_straight_line = Path.isStraightLineHandle(first_handle);
                    if (!is_full_straight_line) {
                        curves[i] = curves[i + 1]; // assign to closest control point
                    }
                }
            }
        }
    }

    pub fn getDrawVertexData(self: Path, allocator: std.mem.Allocator, preview_point: ?Point) !?[]const Point {
        const option_curves = try self.getClosedPathPoints(allocator, preview_point);
        if (option_curves) |curves| {
            Path.prepareHalfStraightLines(curves);

            return curves;
        } else {
            return null;
        }
    }

    pub fn updateLastHandle(self: *Path, preview_point: Point) void {
        const points = self.points.items;
        if (self.closed) {
            points[points.len - 2] = getOppositeHandle(points[0], preview_point);
            points[1] = preview_point;
        } else {
            if (points.len == 2) { // there is only starting control point(no reflection of handle needed)
                points[points.len - 1] = preview_point;
            } else {
                const control_point = points[points.len - 1];
                points[points.len - 2] = getOppositeHandle(control_point, preview_point);
            }
        }
    }

    pub fn serialize(self: Path) []const Point {
        return self.points.items;
    }

    pub fn deinit(self: *Path) void {
        self.points.deinit();
    }
};
