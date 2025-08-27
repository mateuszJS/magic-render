const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");
const shared = @import("../shared.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const PackedPickId = @import("packed_pick_id.zig");
const PathUtils = @import("path_utils.zig");

const SKELETON_POINT_SIZE = 10.0;
const PICK_POINT_SCALE = 2.0;

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

    pub fn newFromPoints(path: []const Point, same_point_threshold: Point, allocator: std.mem.Allocator) !Path {
        var point_list = std.ArrayList(Point).init(allocator);
        var closed = false;

        for (path, 0..) |point, i| {
            try point_list.append(point);

            if (i > 0 and i == path.len - 1) {
                if (@abs(path[0].x - point.x) < same_point_threshold.x and @abs(path[0].y - point.y) < same_point_threshold.y) {
                    closed = true;
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
            try self.points.append(PathUtils.getOppositeHandle(last_cp, last_handle));
        }

        try self.points.append(PathUtils.STRAIGHT_LINE_HANDLE);

        const first_point = self.points.items[0];

        if (@abs(first_point.x - point.x) < same_point_threshold.x and @abs(first_point.y - point.y) < same_point_threshold.y) {
            self.closed = true;
            try self.points.append(first_point);
        } else {
            try self.points.append(point);
        }
    }

    pub fn getVertexDrawSkeletonPoint(is_control_point: bool, point: Point, is_hovered: bool) [2]triangles.DrawInstance {
        var buffer: [2]triangles.DrawInstance = undefined;
        const color = if (is_hovered) [_]u8{ 0, 255, 0, 255 } else [_]u8{ 0, 0, 255, 255 };
        const size = SKELETON_POINT_SIZE * shared.render_scale;

        if (is_control_point) {
            squares.getDrawVertexData(
                buffer[0..2],
                point.x - size / 2.0,
                point.y - size / 2.0,
                size,
                size,
                0.0,
                color,
            );
        } else {
            squares.getDrawVertexData(
                buffer[0..2],
                point.x - size / 2.0,
                point.y - size / 2.0,
                size,
                size,
                size / 2.0,
                color,
            );
        }
        return buffer;
    }

    pub fn getVertexPickSkeletonPoint(is_control_point: bool, point: Point, id: u32) [2]triangles.PickInstance {
        var buffer: [2]triangles.PickInstance = undefined;
        const size = SKELETON_POINT_SIZE * PICK_POINT_SCALE * shared.render_scale;

        if (is_control_point) {
            squares.getPickVertexData(
                buffer[0..2],
                point.x - size / 2.0,
                point.y - size / 2.0,
                size,
                size,
                0.0,
                id,
            );
        } else {
            squares.getPickVertexData(
                buffer[0..2],
                point.x - size / 2.0,
                point.y - size / 2.0,
                size,
                size,
                size / 2.0,
                id,
            );
        }
        return buffer;
    }

    pub fn getSkeletonDrawVertexData(
        self: Path,
        matrix: Matrix3x3,
        allocator: std.mem.Allocator,
        hover_id: ?PackedPickId.PointId,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.points.items, 0..) |relative_point, i| {
            if (PathUtils.isStraightLineHandle(relative_point)) {
                // This is a straight line handle, skip it
                continue;
            }

            const point = matrix.get(relative_point);
            const is_hovered = if (hover_id) |h| h.point == i else false;

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

            const buffer = Path.getVertexDrawSkeletonPoint(is_control_point, point, is_hovered);
            try skeleton_buffer.appendSlice(&buffer);
        }

        const last_handle_norm = self.points.items[self.points.items.len - 2];
        if (!self.closed and self.points.items.len != 2 and !PathUtils.isStraightLineHandle(last_handle_norm)) {
            const last_handle = matrix.get(last_handle_norm);
            const last_cp = matrix.get(self.points.getLast());
            const forward_handle = PathUtils.getOppositeHandle(last_cp, last_handle);
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

            const square_buffer = Path.getVertexDrawSkeletonPoint(false, forward_handle, false);
            try skeleton_buffer.appendSlice(&square_buffer);
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
            const is_control_point = i % 4 == 0 or i % 4 == 3;
            const id = PackedPickId.encode(shape_id, path_index, i);
            const buffer = Path.getVertexPickSkeletonPoint(is_control_point, point, id);
            try skeleton_buffer.appendSlice(&buffer);
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getClosedPathPoints(self: Path, buffer: *std.ArrayList(Point), preview_point: ?Point) !void {
        if (self.points.items.len <= 2 and preview_point == null) {
            return;
        }

        // Copy points manually
        for (self.points.items) |point| {
            try buffer.append(point);
        }

        if (!self.closed) {
            if (preview_point) |preview| {
                if (self.points.items.len > 2) {
                    const last_cp = self.points.getLast().clone();
                    const last_handle = self.points.items[self.points.items.len - 2].clone();
                    try buffer.append(last_cp);
                    try buffer.append(PathUtils.getOppositeHandle(last_cp, last_handle));
                }

                try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
                try buffer.append(preview);
            }

            const last_curve_point = buffer.getLast().clone();
            const first_curve_point = self.points.items[0].clone();
            try buffer.append(last_curve_point);
            try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
            try buffer.append(PathUtils.STRAIGHT_LINE_HANDLE);
            try buffer.append(first_curve_point);
        }
    }

    pub fn updateLastHandle(self: *Path, preview_point: Point) void {
        const points = self.points.items;
        if (self.closed) {
            points[points.len - 2] = PathUtils.getOppositeHandle(points[0], preview_point);
            points[1] = preview_point;
        } else {
            if (points.len == 2) { // there is only starting control point(no reflection of handle needed)
                points[points.len - 1] = preview_point;
            } else {
                const control_point = points[points.len - 1];
                points[points.len - 2] = PathUtils.getOppositeHandle(control_point, preview_point);
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
