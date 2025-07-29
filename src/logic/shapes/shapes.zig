const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");

pub const Shape = struct {
    id: u32,
    points: std.ArrayList(Point),
    stroke_width: f32,

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice

    pub fn init(id: u32, points: []const Point, allocator: std.mem.Allocator) !Shape {
        var point_list = std.ArrayList(Point).init(allocator);
        try point_list.appendSlice(points);

        return Shape{
            .id = id,
            .points = point_list,
            .stroke_width = 20.0,
        };
    }

    // Alternative: Create empty shape and add points later
    pub fn initEmpty(id: u32, allocator: std.mem.Allocator) Shape {
        return Shape{
            .id = id,
            .points = std.ArrayList(Point).init(allocator),
        };
    }

    pub fn add_point(self: *Shape, point: Point) void {
        self.points.append(point) catch unreachable;
    }

    pub fn deinit(self: *Shape) void {
        std.debug.print("Deinitializing Shape with {} points\n", self.points.items.len);
        self.points.deinit();
    }

    pub fn get_draw_vertex_data(self: Shape, allocator: std.mem.Allocator) !VertexOutput {
        // Allocate exact size needed
        const curves = try allocator.alloc(Point, self.points.items.len + 1);

        // Copy points manually
        for (self.points.items, 0..) |point, i| {
            curves[i] = point;
        }
        curves[curves.len - 1] = self.points.items[0]; // repeat first point

        const box = bounding_box.getBoundingBox(curves, self.stroke_width, allocator);

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
