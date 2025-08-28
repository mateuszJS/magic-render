const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../lines.zig");
const shared = @import("../shared.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const PackedId = @import("packed_id.zig");
const PathUtils = @import("path_utils.zig");

pub const Path = struct {
    points: std.ArrayList(Point),
    handle_zero: ?Point,

    pub fn new(point: Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.append(point);

        const shape = Path{
            .points = point_list,
            .handle_zero = PathUtils.STRAIGHT_LINE_HANDLE,
        };

        return shape;
    }

    pub fn newFromPoints(path: []const Point, same_point_threshold: Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        var handle_zero: ?Point = null;

        for (path, 0..) |point, i| {
            try point_list.append(point);

            if (i > 0 and i == path.len - 1) {
                if (@abs(path[0].x - point.x) < same_point_threshold.x and @abs(path[0].y - point.y) < same_point_threshold.y) {
                    handle_zero = null;
                }
            }
        }

        return Path{
            .points = point_list,
            .handle_zero = handle_zero,
        };
    }

    pub fn addPoint(self: *Path, point: Point, same_point_threshold: Point) !void {
        if (self.handle_zero) |handle_zero| {
            const prev_handle = if (self.points.items.len == 1)
                handle_zero
            else
                self.points.items[self.points.items.len - 2];
            // The drop shape should be possible, but it's not right now

            const last_cp = self.points.getLast().clone();
            const next_handle = PathUtils.getOppositeHandle(last_cp, prev_handle);

            try self.points.append(next_handle);
            try self.points.append(PathUtils.STRAIGHT_LINE_HANDLE);

            const first_point = self.points.items[0];
            if (@abs(first_point.x - point.x) < same_point_threshold.x and @abs(first_point.y - point.y) < same_point_threshold.y) {
                self.handle_zero = null;
                // try self.points.append(first_point);
            } else {
                try self.points.append(point);
            }
        } else {
            @panic("Attempting to add point to already closed path!");
        }
    }

    fn getPrevHandle(self: Path, i: usize) ?Point {
        const points = self.points.items;
        if (i > 0) {
            return points[i - 1];
        } else if (i == 0) {
            if (self.handle_zero) |h| {
                return h;
            } else {
                return points[points.len - 1];
            }
        }
        return null;
    }

    fn getNextHandle(self: Path, i: usize) ?Point {
        const points = self.points.items;
        if (points.len == 1) {
            if (self.handle_zero) |h| {
                return PathUtils.getOppositeHandle(points[0], h);
            } else {
                return null;
            }
        }
        if (i == points.len - 1) {
            return PathUtils.getOppositeHandle(points[i], points[i - 1]);
        }
        if (i < points.len - 1) {
            return points[i + 1];
        }
        return null;
    }

    pub fn getSkeletonDrawVertexData(
        self: Path,
        matrix: Matrix3x3,
        allocator: std.mem.Allocator,
        hover_id: ?PackedId.PointId,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const points = self.points.items;

        for (points, 0..) |relative_point, i| {
            if (i % 3 == 0) {
                const cp = matrix.get(relative_point);
                var handles = [2]?Point{
                    self.getPrevHandle(i),
                    self.getNextHandle(i),
                };

                if (handles[0]) |h| {
                    if (PathUtils.isStraightLineHandle(h)) {
                        handles[0] = null;
                    }
                    handles[0] = matrix.get(h);
                }

                if (handles[1]) |h| {
                    if (PathUtils.isStraightLineHandle(h)) {
                        handles[1] = null;
                    }
                    handles[1] = matrix.get(h);
                }

                try PathUtils.drawControlPoint(
                    i,
                    points.len,
                    cp,
                    handles,
                    &skeleton_buffer,
                    hover_id,
                );
            }
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getSkeletonPickVertexData(
        self: Path,
        matrix: Matrix3x3,
        allocator: std.mem.Allocator,
        shape_id: u32,
        path_index: u32,
    ) ![]triangles.PickInstance {
        var skeleton_buffer = std.ArrayList(triangles.PickInstance).init(allocator);
        for (self.points.items, 0..) |relative_point, i| {
            if (PathUtils.isStraightLineHandle(relative_point)) {
                // This is a straight line handle, skip it
                continue;
            }

            const point = matrix.get(relative_point);
            const is_control_point = i % 3 == 0;
            const id = PackedId.encode(shape_id, path_index, i);
            const buffer = PathUtils.getVertexPickSkeletonPoint(is_control_point, point, id);
            try skeleton_buffer.appendSlice(&buffer);
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getClosedPathPoints(self: Path, buffer: *std.ArrayList(Point), preview_point: ?Point) !void {
        const points = self.points.items;

        if (points.len <= 1 and preview_point == null) {
            return;
        }

        for (points, 0..) |point, i| {
            if (i != 0 and i % 3 == 0 and (i != points.len - 1 or self.handle_zero != null)) {
                // inser duplicat(to start a new path) if:
                // its not the first point
                // it is a control point
                // if it's last point, make sure path is not closed
                try buffer.append(point);
            }
            try buffer.append(point);
        }

        if (self.handle_zero) |handle_zero| {
            if (preview_point) |preview| {
                const last_handle = if (points.len == 1)
                    handle_zero
                else
                    points[points.len - 2];

                const last_cp = self.points.getLast();
                try buffer.append(PathUtils.getOppositeHandle(last_cp, last_handle));
                try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
                try buffer.append(preview);
                try buffer.append(preview);
            }

            const first_curve_point = points[0].clone();
            try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
            try buffer.append(handle_zero);
            try buffer.append(first_curve_point);
        } else {
            try buffer.append(points[0]);
        }
    }

    pub fn updateLastHandle(self: *Path, preview_point: Point) void {
        const points = self.points.items;

        const cp = if (self.handle_zero == null) points[0] else points[points.len - 1];
        const opposite_handle = PathUtils.getOppositeHandle(cp, preview_point);

        if (self.handle_zero == null) {
            points[1] = preview_point;
            points[points.len - 1] = opposite_handle;
        } else if (self.points.items.len == 1) {
            self.handle_zero = opposite_handle;
        } else {
            points[points.len - 2] = opposite_handle;
        }
    }

    pub fn serialize(self: Path) []const Point {
        return self.points.items;
    }

    pub fn deinit(self: *Path) void {
        self.points.deinit();
    }
};
