const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../line.zig");
const Path = @import("paths.zig").Path;
const shared = @import("../shared.zig");
const images = @import("../images.zig");

const EPSILON = std.math.floatEps(f32);

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

pub const ShapeProps = struct {
    // f32 instead of u8 because Uniforms in wgsl doesn't support u8 anyway
    fill_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default fill color (red)
    stroke_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default stroke color (green)
    stroke_width: f32 = 0.0, // Default stroke width
};

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: ShapeProps,
    // texture related
    points: [4]PointUV = undefined,
    texture_id: ?u32 = null,
    texture_width: f32 = 0.0,
    texture_height: f32 = 0.0,
    invalid_cache: bool = false, // if true, we need to update the cache texture

    pub fn new(id: u32, allocator: std.mem.Allocator) !Shape {
        const shape = Shape{
            .id = id,
            .paths = std.ArrayList(Path).init(allocator),
            .props = ShapeProps{
                .fill_color = .{ 1.0, 1.0, 1.0, 1.0 }, // Red
                .stroke_color = .{ 0.0, 0.0, 0.0, 1.0 }, // Green
                .stroke_width = 2.0,
            },
        };

        return shape;
    }

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice
    pub fn new_from_points(id: u32, input_paths: []const []const [4]Point, props: ShapeProps, allocator: std.mem.Allocator) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(input_path, allocator);
            try paths_list.append(path);
        }

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .invalid_cache = true,
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

    // returns null if path is done and is no lonnger active or id if it's active
    pub fn addPointStart(self: *Shape, allocator: std.mem.Allocator, point: Point, option_active_path_index: ?usize) !usize {
        if (option_active_path_index) |active_path_index| {
            var active_path = &self.paths.items[active_path_index];
            const closed = try active_path.addPoint(point);
            _ = closed; // autofix
            // if (closed) {
            //     return null;
            // }
            self.invalid_cache = true;
            return active_path_index;
        } else {
            // if there is no active path, we create a new one
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            return self.paths.items.len - 1;
        }
    }

    // receives boolean indicating if texture size was updated or not
    pub fn updateTextureSize(self: *Shape) bool {
        const width = self.points[0].distance(self.points[1]);
        const height = self.points[0].distance(self.points[3]);
        const new_width = @min(Utils.get_next_power_of_two(@max(self.texture_width, width / shared.render_scale)), max_texture_size);
        const new_height = @min(Utils.get_next_power_of_two(@max(self.texture_height, height / shared.render_scale)), max_texture_size);

        if (self.texture_width > new_width - EPSILON and self.texture_height > new_height - EPSILON) {
            return false; // No resize needed
        }

        self.texture_width = new_width;
        self.texture_height = new_height;

        return true;
    }

    pub fn drawTextureCache(self: *Shape, allocator: std.mem.Allocator, force: bool) !void {
        if (!self.invalid_cache and !force) return; // texture is up to date

        const option_vertex_output = try self.get_draw_vertex_data(allocator, null, null);
        if (option_vertex_output) |vertex_output| {
            const left_bottom = vertex_output.bounding_box[0];
            const right_top = vertex_output.bounding_box[2];
            self.points = [4]PointUV{
                .{ .x = left_bottom.x, .y = right_top.y, .u = 0.0, .v = 1.0 },
                .{ .x = right_top.x, .y = right_top.y, .u = 1.0, .v = 1.0 },
                .{ .x = right_top.x, .y = left_bottom.y, .u = 1.0, .v = 0.0 },
                .{ .x = left_bottom.x, .y = left_bottom.y, .u = 0.0, .v = 0.0 },
            };

            if (self.texture_width < EPSILON) {
                // we need to calculate bounding box first(we did this above) to set initial size
                _ = self.updateTextureSize();
            }

            const cache_bounding_box = bounding_box.BoundingBox{
                .min_x = left_bottom.x,
                .min_y = left_bottom.y,
                .max_x = right_top.x,
                .max_y = right_top.y,
            };

            self.texture_id = cache_shape(
                self.texture_id,
                cache_bounding_box,
                vertex_output,
                self.texture_width,
                self.texture_height,
            );
            self.invalid_cache = false;
        }
    }

    pub fn get_skeleton_draw_vertex_data(self: Shape, allocator: std.mem.Allocator, preview_point: ?Point, is_handle_preview: bool) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.paths.items) |path| {
            const path_skeleton = try path.get_skeleton_draw_vertex_data(allocator);
            try skeleton_buffer.appendSlice(path_skeleton);
        }

        if (preview_point) |point| {
            if (!is_handle_preview) {
                const size = 20.0 * shared.render_scale;
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
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn get_draw_vertex_data(self: Shape, allocator: std.mem.Allocator, active_path_index: ?usize, option_preview_point: ?Point) !?DrawVertexOutput {
        var curves_buffer = std.ArrayList(Point).init(allocator);
        for (self.paths.items, 0..) |path, i| {
            const preview_point = if (active_path_index == i) option_preview_point else null;
            const option_curves = try path.get_draw_vertex_data(allocator, preview_point);
            if (option_curves) |curves| {
                try curves_buffer.appendSlice(curves);
            }
        }

        if (curves_buffer.items.len > 0) {
            // Shape.prepare_half_straight_lines(curves);

            const box = bounding_box.getBoundingBox(curves_buffer.items, self.props.stroke_width / 2.0);
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
                    .stroke_width = self.props.stroke_width,
                    .fill_color = self.props.fill_color,
                    .stroke_color = self.props.stroke_color,
                },
            };
        } else {
            return null;
        }
    }

    pub fn getCacheTextureDrawVertexData(self: Shape) images.DrawVertex {
        return images.DrawVertex{
            // first triangle
            self.points[0],
            self.points[1],
            self.points[2],
            // second triangle
            self.points[2],
            self.points[3],
            self.points[0],
        };
    }

    pub fn getCacheTexturePickVertexData(self: Shape) [6]images.PickVertex {
        return [_]images.PickVertex{
            // first triangle
            .{ .id = self.id, .point = self.points[0] },
            .{ .id = self.id, .point = self.points[1] },
            .{ .id = self.id, .point = self.points[2] },
            // second triangle
            .{ .id = self.id, .point = self.points[2] },
            .{ .id = self.id, .point = self.points[3] },
            .{ .id = self.id, .point = self.points[0] },
        };
    }

    pub fn updateLastHandle(self: *Shape, active_path_index: usize, preview_point: Point) void {
        const active_path = self.paths.items[active_path_index];
        const points = active_path.points.items;

        if (active_path.closed) {
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

        self.invalid_cache = true;
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
