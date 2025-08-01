const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");

const STRAIGHT_LINE_THRESHOLD = 1e+10;
const STRAIGHT_LINE_HANDLE = Point{
    .x = 1e+11,
    .y = 0.0,
};

fn getOppositeHandle(control_point: Point, handle: Point) Point {
    const diff = control_point.diff(handle);
    const opposite_point = Point{
        .x = control_point.x + diff.x,
        .y = control_point.y + diff.y,
    };

    return opposite_point;
}

pub const Shape = struct {
    id: u32,
    points: std.ArrayList(Point),
    stroke_width: f32,
    preview_point: ?Point = null, // Optional preview points for rendering
    is_handle_preview: bool = false, // Whether to show the preview point as a handle
    is_closed: bool = false, // Whether the shape is closed

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice
    pub fn new(id: u32, point: Point, allocator: std.mem.Allocator) !Shape {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.append(point);
        try point_list.append(STRAIGHT_LINE_HANDLE);

        const shape = Shape{
            .id = id,
            .points = point_list,
            .stroke_width = 20.0,
            .is_handle_preview = true,
        };

        return shape;
    }

    pub fn add_point_start(self: *Shape) !void {
        if (self.preview_point) |point| {
            const first_point = self.points.items[0];
            const distance = first_point.distance(point);
            try self.points.append(STRAIGHT_LINE_HANDLE);
            if (distance < 10.0) {
                // path is closed
                self.is_closed = true;
            } else {
                try self.points.append(point);
                try self.points.append(STRAIGHT_LINE_HANDLE);
            }
            self.preview_point = null;
            self.is_handle_preview = true;
        }
    }

    pub fn add_point_end(self: *Shape) !void {
        self.is_handle_preview = false;
    }

    pub fn get_draw_vertex_data(self: Shape, allocator: std.mem.Allocator) !?VertexOutput {
        var curves = std.ArrayList(Point).init(allocator);

        // Copy points manually
        for (self.points.items) |point| {
            try curves.append(point);
        }

        if (!self.is_closed) {
            if (self.preview_point) |preview| {
                if (!self.is_handle_preview) {
                    try curves.append(STRAIGHT_LINE_HANDLE);
                    try curves.append(preview);
                }
                try curves.append(STRAIGHT_LINE_HANDLE);
            }
        }

        var preview_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const size = 20.0;

        for (self.points.items, 0..) |point, i| {
            const is_control_point = i % 3 == 0;
            if (!is_control_point) {
                if (point.x > STRAIGHT_LINE_THRESHOLD) {
                    // This is a straight line handle, skip it
                    continue;
                }
                const connected_control_point = if (i % 3 == 1) i - 1 else (i + 1) % self.points.items.len;
                var buffer: [2]triangles.DrawInstance = undefined;
                lines.get_draw_vertex_data(
                    buffer[0..2],
                    self.points.items[connected_control_point],
                    point,
                    3.0,
                    [_]u8{ 0, 0, 255, 255 },
                    0.0,
                );
                try preview_buffer.appendSlice(&buffer);
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
            try preview_buffer.appendSlice(&buffer);
        }

        // close the shape for ray casting/winding number
        if (!self.is_closed) {
            try curves.append(STRAIGHT_LINE_HANDLE);
        }
        try curves.append(self.points.items[0]); // repeat first point

        var final_curves = curves.items;

        // Handle half straight lines to be treated as bezier curves
        for (final_curves, 0..) |point, i| {
            const is_straight_line_handle = point.x >= STRAIGHT_LINE_THRESHOLD;
            if (final_curves.len >= 4 and is_straight_line_handle) {
                if (i % 3 == 1) { // first handle
                    const second_handle = final_curves[i + 1];
                    const is_full_straight_line = second_handle.x >= STRAIGHT_LINE_THRESHOLD;
                    if (!is_full_straight_line) {
                        final_curves[i] = final_curves[i - 1]; // assign to closest control point
                    }
                } else if (i % 3 == 2) { // second handle
                    const first_handle = final_curves[i - 1];
                    const is_full_straight_line = first_handle.x >= STRAIGHT_LINE_THRESHOLD;
                    if (!is_full_straight_line) {
                        final_curves[i] = final_curves[i + 1]; // assign to closest control point
                    }
                }
            }
        }

        const box = bounding_box.getBoundingBox(final_curves, self.stroke_width);

        return VertexOutput{
            .curves = final_curves, // Transfer ownership directly
            .bounding_box = box,
            .uniform = Uniform{
                .stroke_width = self.stroke_width,
                .fill_color = [4]f32{ 1.0, 0.0, 0.0, 1.0 },
                .stroke_color = [4]f32{ 0.0, 1.0, 0.0, 1.0 },
            },
            .preview_buffer = preview_buffer.items, // Transfer ownership directly
        };
    }

    pub fn setPreviewPoint(self: *Shape, point: Point) void {
        var points = self.points.items;
        const control_point = points[points.len - 2];

        if (self.is_handle_preview) {
            if (self.is_closed) {
                points[points.len - 1] = getOppositeHandle(points[0], point);
                points[1] = point;
            } else {
                points[points.len - 1] = point;
                if (points.len != 2) { // there is only starting control point(no reflection of handle needed)
                    points[points.len - 3] = getOppositeHandle(control_point, point);
                }
            }
        } else {
            const distance = control_point.distance(point);
            if (distance < 10.0) {
                self.preview_point = null;
            } else {
                self.preview_point = point;
            }
        }
    }

    pub fn deinit(self: *Shape) void {
        self.points.deinit();
    }
};

const VertexOutput = struct {
    curves: []const Point,
    bounding_box: [6]Point,
    uniform: Uniform,
    preview_buffer: []triangles.DrawInstance,
};

pub const Uniform = extern struct {
    stroke_width: f32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // Padding for alignment
    fill_color: [4]f32,
    stroke_color: [4]f32,
};
