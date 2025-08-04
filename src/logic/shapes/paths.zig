const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");
const shared = @import("../shared.zig");

const EPSILON = std.math.floatEps(f32);
const POINT_SNAP_DISTANCE = 10.0; // Minimum distance to consider a new control point
const STRAIGHT_LINE_THRESHOLD = 1e+10;
const STRAIGHT_LINE_HANDLE = Point{
    .x = 1e+11,
    .y = 0.0,
};

fn getOppositeHandle(control_point: Point, handle: Point) Point {
    if (handle.x > STRAIGHT_LINE_THRESHOLD) {
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
    pub fn newFromPoints(path: []const [4]Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        var closed = false;

        for (path, 0..) |curve, i| {
            try point_list.appendSlice(&curve);

            if (i == path.len - 1) {
                const distance = path[0][0].distance(curve[3]);
                if (distance < POINT_SNAP_DISTANCE) {
                    // here is the problem, it should be overlap with exactly one point, then it might be caunted a closed
                    // althouhg the better word might be that a curve is open. More than one curve in a shape might be open!
                    closed = true;
                }
            }
        }

        return Path{
            .points = point_list,
            .closed = closed,
        };
    }

    pub fn addPoint(self: *Path, point: Point) !void {
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
        const distance = first_point.distance(point);

        if (distance < POINT_SNAP_DISTANCE) {
            self.closed = true;
            try self.points.append(first_point);
        } else {
            try self.points.append(point);
        }
    }

    pub fn get_skeleton_draw_vertex_data(self: Path, allocator: std.mem.Allocator) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const size = 20.0 * shared.render_scale;

        for (self.points.items, 0..) |point, i| {
            const is_control_point = i % 4 == 0 or i % 4 == 3;
            if (!is_control_point) {
                if (point.x > STRAIGHT_LINE_THRESHOLD) {
                    // This is a straight line handle, skip it
                    continue;
                }
                const connected_control_point = if (i % 4 == 1) i - 1 else (i + 1) % self.points.items.len;
                var buffer: [2]triangles.DrawInstance = undefined;
                lines.get_draw_vertex_data(
                    buffer[0..2],
                    self.points.items[connected_control_point],
                    point,
                    3.0 * shared.render_scale,
                    [_]u8{ 0, 0, 255, 255 },
                    0.0,
                );
                try skeleton_buffer.appendSlice(&buffer);
            }

            var buffer: [2]triangles.DrawInstance = undefined;
            squares.get_draw_vertex_data(
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

        const last_handle = self.points.items[self.points.items.len - 2];
        if (!self.closed and self.points.items.len != 2 and last_handle.x < STRAIGHT_LINE_THRESHOLD) {
            const last_cp = self.points.getLast();
            const forward_handle = getOppositeHandle(last_cp, last_handle);
            var line_buffer: [2]triangles.DrawInstance = undefined;
            lines.get_draw_vertex_data(
                line_buffer[0..2],
                last_cp,
                forward_handle,
                3.0 * shared.render_scale,
                [_]u8{ 0, 0, 255, 255 },
                0.0,
            );
            try skeleton_buffer.appendSlice(&line_buffer);

            var square_buffer: [2]triangles.DrawInstance = undefined;
            squares.get_draw_vertex_data(
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

    fn get_closed_path_points(self: Path, allocator: std.mem.Allocator, preview_point: ?Point) !?[]Point {
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

    fn prepare_half_straight_lines(curves: []Point) void {
        if (curves.len < 4) {
            return; // Not enough points to process
        }
        // Handle half straight lines to be treated as bezier curves
        for (curves, 0..) |point, i| {
            const is_straight_line_handle = point.x > STRAIGHT_LINE_THRESHOLD;
            if (is_straight_line_handle) {
                if (i % 4 == 1) { // first handle
                    const second_handle = curves[i + 1];
                    const is_full_straight_line = second_handle.x > STRAIGHT_LINE_THRESHOLD;
                    if (!is_full_straight_line) {
                        curves[i] = curves[i - 1]; // assign to closest control point
                    }
                } else if (i % 4 == 2) { // second handle
                    const first_handle = curves[i - 1];
                    const is_full_straight_line = first_handle.x > STRAIGHT_LINE_THRESHOLD;
                    if (!is_full_straight_line) {
                        curves[i] = curves[i + 1]; // assign to closest control point
                    }
                }
            }
        }
    }

    pub fn get_draw_vertex_data(self: Path, allocator: std.mem.Allocator, preview_point: ?Point) !?[]const Point {
        const option_curves = try self.get_closed_path_points(allocator, preview_point);
        if (option_curves) |curves| {
            Path.prepare_half_straight_lines(curves);

            return curves;
        } else {
            return null;
        }
    }

    pub fn deinit(self: *Path) void {
        self.points.deinit();
    }
};
