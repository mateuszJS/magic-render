const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");
const Path = @import("paths.zig").Path;
const shared = @import("../shared.zig");

const EPSILON = std.math.floatEps(f32);
const MIN_NEW_CONTROL_POINT_DISTANCE = 10.0; // Minimum distance to consider a new control point

fn getOppositeHandle(control_point: Point, handle: Point) Point {
    const diff = control_point.diff(handle);
    const opposite_point = Point{
        .x = control_point.x + diff.x,
        .y = control_point.y + diff.y,
    };

    return opposite_point;
}

pub var cache_shape: *const fn (?u32, bounding_box.BoundingBox, DrawVertexOutput, f32, f32) u32 = undefined;
pub var max_texture_size: f32 = 0.0;

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    stroke_width: f32,
    preview_point: ?Point = null, // Optional preview points for rendering
    is_handle_preview: bool = false, // Whether to show the preview point as a handle
    active_path_index: ?usize = null, // Index of the active path for editing

    // texture related
    bounding_box: bounding_box.BoundingBox = undefined,
    texture_id: ?u32 = null,
    texture_width: f32 = 0.0,
    texture_height: f32 = 0.0,

    pub fn new(id: u32, point: Point, allocator: std.mem.Allocator) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);
        const path = try Path.new(point, allocator);
        try paths_list.append(path);

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .stroke_width = 10.0,
            .is_handle_preview = true,
            .active_path_index = 0,
        };

        return shape;
    }

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice
    pub fn new_from_points(id: u32, input_paths: []const []const [2]Point, allocator: std.mem.Allocator) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(input_path, allocator);
            try paths_list.append(path);
        }

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .stroke_width = 10.0,
            .is_handle_preview = false,
            .active_path_index = 0,
        };

        return shape;
    }

    // fn is_matching_open_point(self: *Shape, point: Point) ?Point {
    //     var result = null;
    //     // maybe isntead we should have a list of open points, and then use it during the render?
    //     for (self.points.items, 0..) |p, i| {
    //         var is_open = false;
    //         if (i % 4 == 0) { // first cp
    //             const distance = p.distance(self.points.items[i + 3]);
    //             if (distance > 10.0) {
    //                 is_open = true;
    //             }
    //         } else if (i % 4 == 3) { // second cp
    //             const distance = p.distance(self.points.items[i - 1]);
    //             if (distance > 10.0) {
    //                 is_open = true;
    //             }
    //         }

    //         if (is_open) {
    //             const distance = p.distance(point);
    //             if (distance < 10.0) {
    //                 result = p;
    //             }
    //         }
    //     }
    //     return result;
    // }

    // return bool indicating if shape is done or not
    pub fn addPointStart(self: *Shape) !void {
        if (self.preview_point) |point| {
            if (self.active_path_index) |active_path_index| {
                var active_path = &self.paths.items[active_path_index];
                try active_path.addPoint(point);
                self.preview_point = null;
                self.is_handle_preview = true;

                // if (active_path.closed) {
                //     self.active_path_index = null;
                // }
            } else {
                // if there is no active path, we create a new one
                const new_path = try Path.new(point, self.paths.allocator);
                try self.paths.append(new_path);
                self.active_path_index = self.paths.items.len - 1;
                self.is_handle_preview = true;
            }
        }
    }

    pub fn add_point_end(self: *Shape) !void {
        self.is_handle_preview = false;
    }

    pub fn complete(self: *Shape, allocator: std.mem.Allocator) !void {
        self.is_handle_preview = false;
        self.preview_point = null;

        try self.drawTextureCache(allocator);
    }

    // receives boolean indicating if texture size was updated or not
    pub fn updateTextureSize(self: *Shape) bool {
        const width = self.bounding_box.max_x - self.bounding_box.min_x;
        const height = self.bounding_box.max_y - self.bounding_box.min_y;
        const new_width = @min(Utils.get_next_power_of_two(@max(self.texture_width, width / shared.render_scale)), max_texture_size);
        const new_height = @min(Utils.get_next_power_of_two(@max(self.texture_height, height / shared.render_scale)), max_texture_size);

        if (self.texture_width >= new_width - EPSILON and self.texture_height >= new_height - EPSILON) {
            return false; // No resize needed
        }

        self.texture_width = new_width;
        self.texture_height = new_height;

        return true;
    }

    pub fn drawTextureCache(self: *Shape, allocator: std.mem.Allocator) !void {
        const option_vertex_output = try self.get_draw_vertex_data(allocator);
        if (option_vertex_output) |vertex_output| {
            self.bounding_box = bounding_box.BoundingBox{
                .min_x = vertex_output.bounding_box[0].x,
                .min_y = vertex_output.bounding_box[0].y,
                .max_x = vertex_output.bounding_box[2].x,
                .max_y = vertex_output.bounding_box[2].y,
            };

            if (self.texture_width < EPSILON) {
                // we need to calculate bounding box first(we did this above) to set initial size
                _ = self.updateTextureSize();
            }

            self.texture_id = cache_shape(self.texture_id, self.bounding_box, vertex_output, self.texture_width, self.texture_height);
        }
    }

    pub fn get_skeleton_draw_vertex_data(self: Shape, allocator: std.mem.Allocator) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.paths.items) |path| {
            const path_skeleton = try path.get_skeleton_draw_vertex_data(allocator);
            try skeleton_buffer.appendSlice(path_skeleton);
        }

        if (self.preview_point) |preview| {
            if (!self.is_handle_preview) {
                const size = 20.0 * shared.render_scale;
                var buffer: [2]triangles.DrawInstance = undefined;
                squares.get_draw_vertex_data(
                    buffer[0..2],
                    preview.x - size / 2.0,
                    preview.y - size / 2.0,
                    size,
                    size,
                    0.0,
                    [_]u8{ 0, 0, 255, 255 },
                );
                try skeleton_buffer.appendSlice(&buffer);
            }
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn get_draw_vertex_data(self: Shape, allocator: std.mem.Allocator) !?DrawVertexOutput {
        var curves_buffer = std.ArrayList(Point).init(allocator);
        for (self.paths.items, 0..) |path, i| {
            const preview_point = if (self.active_path_index == i) self.preview_point else null;
            const option_curves = try path.get_draw_vertex_data(allocator, preview_point);
            if (option_curves) |curves| {
                try curves_buffer.appendSlice(curves);
            }
        }

        if (curves_buffer.items.len > 0) {
            // Shape.prepare_half_straight_lines(curves);

            const box = bounding_box.getBoundingBox(curves_buffer.items, self.stroke_width / 2.0);
            const box_vertex = [6]Point{
                // First triangle
                .{ .x = box.min_x, .y = box.min_y }, // bottom-left
                .{ .x = box.max_x, .y = box.min_y }, // bottom-right
                .{ .x = box.max_x, .y = box.max_y }, // top-right

                // Second triangle
                .{ .x = box.max_x, .y = box.max_y }, // top-right
                .{ .x = box.min_x, .y = box.max_y }, // top-left
                .{ .x = box.min_x, .y = box.min_y }, // bottom-left
            };

            return DrawVertexOutput{
                .curves = curves_buffer.items, // Transfer ownership directly
                .bounding_box = box_vertex,
                .uniform = Uniform{
                    .stroke_width = self.stroke_width,
                    .fill_color = [4]f32{ 1.0, 0.0, 0.0, 1.0 },
                    .stroke_color = [4]f32{ 0.0, 1.0, 0.0, 1.0 },
                },
            };
        } else {
            return null;
        }
    }

    pub fn setPreviewPoint(self: *Shape, point: Point) void {
        if (self.active_path_index) |active_path_index| {
            const active_path = self.paths.items[active_path_index];
            const points = active_path.points.items;
            const control_point = points[points.len - 1];

            if (self.is_handle_preview) {
                if (active_path.closed) {
                    points[points.len - 2] = getOppositeHandle(points[0], point);
                    points[1] = point;
                } else {
                    if (points.len == 2) { // there is only starting control point(no reflection of handle needed)
                        points[points.len - 1] = point;
                    } else {
                        points[points.len - 2] = getOppositeHandle(control_point, point);
                    }
                }
            } else {
                const distance = control_point.distance(point);
                if (distance < MIN_NEW_CONTROL_POINT_DISTANCE) {
                    self.preview_point = null;
                    return;
                } else {
                    self.preview_point = point;
                }
            }
        }
    }

    pub fn deinit(self: *Shape) void {
        for (self.paths.items) |path| {
            path.deinit();
        }
        self.paths.deinit();
    }
};

pub const DrawVertexOutput = struct {
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
