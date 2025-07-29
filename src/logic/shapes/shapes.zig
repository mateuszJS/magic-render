const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");

pub const Shape = struct {
    id: u32,
    points: std.ArrayList(Point),
    stroke_width: f32,
    preview_point: ?Point = null, // Optional preview points for rendering

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice

    pub fn new(id: u32, points: []const Point, allocator: std.mem.Allocator) !Shape {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.appendSlice(points);

        const shape = Shape{
            .id = id,
            .points = point_list,
            .stroke_width = 20.0,
        };

        return shape;
    }

    pub fn add_point(self: *Shape) void {
        if (self.preview_point) |point| {
            self.points.append(point) catch unreachable;
            self.preview_point = null; // Clear the preview point after adding
        }
    }

    pub fn deinit(self: *Shape) void {
        self.points.deinit();
    }

    pub fn get_draw_vertex_data(self: Shape, allocator: std.mem.Allocator) !VertexOutput {
        // Allocate exact size needed
        var curves_count = self.points.items.len + 1; // +1 for closing the loop
        if (self.preview_point != null) {
            curves_count += 3; // +1 for preview point
        }

        const curves = try allocator.alloc(Point, curves_count);

        // Copy points manually
        for (self.points.items, 0..) |point, i| {
            curves[i] = point;
        }
        if (self.preview_point) |preview| {
            const last_point = self.points.items[self.points.items.len - 1];
            const mid_point = last_point.mid(preview);

            curves[curves.len - 4] = last_point.mid(mid_point); // repeat first point
            curves[curves.len - 3] = mid_point.mid(preview); // repeat first point
            curves[curves.len - 2] = preview; // repeat first point
        }
        curves[curves.len - 1] = self.points.items[0]; // repeat first point

        const box = bounding_box.getBoundingBox(curves, self.stroke_width);

        return VertexOutput{
            .curves = curves, // Transfer ownership directly
            .bounding_box = box,
            .uniform = Uniform{
                .stroke_width = self.stroke_width,
                .fill_color = [4]f32{ 1.0, 0.0, 0.0, 1.0 },
                .stroke_color = [4]f32{ 0.0, 1.0, 0.0, 1.0 },
            },
        };
    }

    pub fn setPreviewPoint(self: *Shape, point: Point) void {
        const last_point = self.points.getLast();
        const distance = last_point.distance(point);
        if (distance < 10.0) {
            self.preview_point = null;
        } else {
            self.preview_point = point;
        }
    }
};

const VertexOutput = struct {
    curves: []const Point,
    bounding_box: [6]Point,
    uniform: Uniform,
};

pub const Uniform = extern struct {
    stroke_width: f32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // Padding for alignment
    fill_color: [4]f32,
    stroke_color: [4]f32,
};
