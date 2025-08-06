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

const EPSILON = std.math.floatEps(f32);

fn getOppositeHandle(control_point: Point, handle: Point) Point {
    const diff = control_point.diff(handle);
    const opposite_point = Point{
        .x = control_point.x + diff.x,
        .y = control_point.y + diff.y,
    };

    return opposite_point;
}

pub var cacheShape: *const fn (?u32, bounding_box.BoundingBox, VectorDrawVertex, f32, f32) u32 = undefined;
pub var maxTextureSize: f32 = 0.0;
const SHADER_TRIANGLE_INDICES = [_]usize{
    0, 1, 2,
    2, 3, 0,
};

pub const ShapeProps = struct {
    // f32 instead of u8 because Uniforms in wgsl doesn't support u8 anyway
    fill_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default fill color (red)
    stroke_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default stroke color (green)
    stroke_width: f32 = 0.0, // Default stroke width
};

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    // points on path are in RELATIVE coordinates to box[4]PointUV
    // this way we can just modify box, not individual points

    props: ShapeProps,
    // texture related
    box: [4]PointUV = undefined,
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
    pub fn newFromPoints(id: u32, input_paths: []const []const [4]Point, props: ShapeProps, allocator: std.mem.Allocator) !Shape {
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

    pub fn newFromTexture(id: u32, points: [4]PointUV, texture_id: u32) Shape {
        return Shape{
            .id = id,
            .box = points,
            .texture_id = texture_id,
            .paths = std.ArrayList(Path).init(std.heap.page_allocator),
            .props = ShapeProps{},
        };
    }

    pub fn addPointStart(self: *Shape, allocator: std.mem.Allocator, point: Point, option_active_path_index: ?usize) !usize {
        if (option_active_path_index) |active_path_index| {
            var active_path = &self.paths.items[active_path_index];
            try active_path.addPoint(point);
            self.invalid_cache = true;
            return active_path_index;
        } else {
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            return self.paths.items.len - 1;
        }
    }

    // receives boolean indicating if texture size was updated or not
    pub fn updateTextureSize(self: *Shape) bool {
        const width = self.box[0].distance(self.box[1]);
        const height = self.box[0].distance(self.box[3]);
        const new_width = @min(Utils.getNextPowerOfTwo(@max(self.texture_width, width / shared.render_scale)), maxTextureSize);
        const new_height = @min(Utils.getNextPowerOfTwo(@max(self.texture_height, height / shared.render_scale)), maxTextureSize);

        if (self.texture_width > new_width - EPSILON and self.texture_height > new_height - EPSILON) {
            return false; // No resize needed
        }

        self.texture_width = new_width;
        self.texture_height = new_height;

        return true;
    }

    pub fn drawTextureCache(self: *Shape, allocator: std.mem.Allocator, force: bool) !void {
        if (!self.invalid_cache and !force) return; // texture is up to date

        const option_vertex_output = try self.getDrawVertexData(
            allocator,
            null,
            null,
        );
        if (option_vertex_output) |vertex_output| {
            const left_bottom = vertex_output.bounding_box[0];
            const right_top = vertex_output.bounding_box[2];
            self.box = [4]PointUV{
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

            self.texture_id = cacheShape(
                self.texture_id,
                cache_bounding_box,
                vertex_output,
                self.texture_width,
                self.texture_height,
            );
            self.invalid_cache = false;
        }
    }

    pub fn getSkeletonDrawVertexData(self: Shape, allocator: std.mem.Allocator, preview_point: ?Point, is_handle_preview: bool) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.paths.items) |path| {
            const path_skeleton = try path.getSkeletonDrawVertexData(allocator);
            try skeleton_buffer.appendSlice(path_skeleton);
        }

        if (preview_point) |point| {
            if (!is_handle_preview) {
                const size = 20.0 * shared.render_scale;
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
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getDrawVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
        active_path_index: ?usize,
        option_preview_point: ?Point,
    ) !?VectorDrawVertex {
        var curves_buffer = std.ArrayList(Point).init(allocator);
        for (self.paths.items, 0..) |path, i| {
            const preview_point = if (active_path_index == i) option_preview_point else null;
            const option_curves = try path.getDrawVertexData(allocator, preview_point);
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

            return VectorDrawVertex{
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

    pub fn updateBox(self: *Shape, box: [4]PointUV) void {
        self.box = box;
    }

    pub fn serialize(self: Shape) !Serialized {
        var paths_list = std.ArrayList([]const Point).init(self.paths.allocator);
        for (self.paths.items) |path| {
            const serialized_path = path.serialize();
            try paths_list.append(serialized_path);
        }

        return Serialized{
            .id = self.id,
            .paths = try paths_list.toOwnedSlice(),
            .props = self.props,
            .texture_id = self.texture_id orelse 0,
            .box = self.box,
        };
    }

    pub fn souldRenderTexture(self: Shape) bool {
        return self.texture_id != null and self.texture_width > EPSILON and self.texture_height > EPSILON;
    }

    pub fn getTextureRenderVertexData(self: Shape, buffer: *TextureDrawVertex) void {
        var i: usize = 0;

        for (SHADER_TRIANGLE_INDICES) |index| {
            buffer[i] = self.box[index];
            i += 1;
        }
    }

    pub fn getTexturePickVertexData(self: Shape, buffer: *[6]TexturePickVertex) void {
        for (SHADER_TRIANGLE_INDICES, 0..) |index, i| {
            buffer[i] = .{
                .point = self.box[index],
                .id = self.id,
            };
        }
    }

    pub fn deinit(self: *Shape) void {
        for (self.paths.items) |path| {
            path.deinit();
        }
        self.paths.deinit();
    }
};

pub const VectorDrawVertex = struct {
    curves: []const Point,
    bounding_box: [6]Point,
    uniform: Uniform,
};

pub const TextureDrawVertex = [6]PointUV;
pub const TexturePickVertex = extern struct { point: PointUV, id: u32 };

pub const Uniform = extern struct {
    stroke_width: f32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // Padding for alignment
    fill_color: [4]f32,
    stroke_color: [4]f32,
};

pub const Serialized = struct {
    id: u32,
    texture_id: u32,
    paths: [][]const Point,
    props: ShapeProps,
    box: [4]PointUV,
};
