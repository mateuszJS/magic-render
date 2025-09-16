const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangles.zig");
const lines = @import("../lines.zig");
const shared = @import("../shared.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const PathUtils = @import("path_utils.zig");

pub const Path = struct {
    points: std.ArrayList(Point),
    closed: bool,

    pub fn new(point: Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.append(point);
        try point_list.append(PathUtils.STRAIGHT_LINE_HANDLE);

        const shape = Path{
            .points = point_list,
            .closed = false,
        };

        return shape;
    }

    pub fn newFromPoints(path: []const Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.appendSlice(path);

        return Path{
            .points = point_list,
            .closed = path.len % 3 == 0,
        };
    }

    pub fn addPoint(self: *Path, point: Point, same_point_threshold: Point) !void {
        if (self.closed) {
            @panic("Attempting to add point to already closed path!");
        }

        if (self.points.items.len > 2) {
            // by default we add point and straight line handle on the start
            // but adding more points always ends path with a control point, not handle at the end
            const prev_handle = self.points.items[self.points.items.len - 2];
            const last_cp = self.points.getLast();
            const next_handle = PathUtils.getOppositeHandle(last_cp, prev_handle);
            try self.points.append(next_handle);
        }

        try self.points.append(PathUtils.STRAIGHT_LINE_HANDLE);

        const first_p = self.points.items[0];
        if (@abs(first_p.x - point.x) < same_point_threshold.x and @abs(first_p.y - point.y) < same_point_threshold.y) {
            self.closed = true;
        } else {
            try self.points.append(point);
        }
    }

    fn getPrevHandle(self: Path, i: usize) ?Point {
        const points = self.points.items;
        if (i > 0) return points[i - 1];
        if (i == 0 and self.closed) return points[points.len - 1];
        return null;
    }

    fn getNextHandle(self: Path, i: usize, with_preview: bool) ?Point {
        const points = self.points.items;
        if (i + 1 <= points.len - 1) return points[i + 1];
        if (i != 0 and with_preview and !self.closed) return PathUtils.getOppositeHandle(points[i], points[i - 1]);
        return null;
    }

    pub fn getSkeletonDrawVertexData(
        self: Path,
        matrix: Matrix3x3,
        allocator: std.mem.Allocator,
        hover_id: ?[4]u32,
        with_preview: bool,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.points.items, 0..) |relative_point, i| {
            if (i % 3 == 0) {
                const cp = matrix.get(relative_point);
                var handles = [2]?Point{
                    self.getPrevHandle(i),
                    self.getNextHandle(i, with_preview),
                };
                for (&handles) |*handle| {
                    if (handle.*) |h| {
                        if (PathUtils.isStraightLineHandle(h)) {
                            handle.* = null;
                        } else {
                            handle.* = matrix.get(h);
                        }
                    }
                }

                try PathUtils.drawControlPoint(
                    i,
                    self.points.items.len,
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
            const id = [4]u32{ shape_id, path_index + 1, i + 1, 0 };
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
            if (i != 0 and i % 3 == 0 and (i != points.len - 1 or !self.closed)) {
                // inser duplicat(to start a new path) if:
                // its not the first point
                // it is a control point
                // if it's last point, make sure path is not closed
                try buffer.append(point);
            }
            try buffer.append(point);
        }

        if (!self.closed) {
            if (preview_point) |preview| {
                if (points.len > 2) {
                    const last_cp = self.points.getLast();
                    const last_handle = points[points.len - 2];
                    try buffer.append(PathUtils.getOppositeHandle(last_cp, last_handle));
                }
                try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
                try buffer.append(preview);
                try buffer.append(preview);
            }

            if (points.len > 2 or preview_point != null) {
                try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
            }
            try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
        }

        try buffer.append(points[0]);
    }

    pub fn updateLastHandle(self: *Path, preview_point: Point) void {
        const points = self.points.items;

        const cp = if (self.closed) points[0] else points[points.len - 1];
        const opposite_handle = PathUtils.getOppositeHandle(cp, preview_point);

        if (self.closed) {
            points[1] = preview_point;
            points[points.len - 1] = opposite_handle;
        } else if (self.points.items.len == 2) {
            points[1] = preview_point;
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
