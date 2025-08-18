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
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;

const POINT_SNAP_DISTANCE = 10.0; // Minimum distance to consider a new control point
const EPSILON = std.math.floatEps(f32);
pub var update_texture_cache: *const fn (u32, bounding_box.BoundingBox, DrawVertexOutput, f32, f32) void = undefined;
pub var maxTextureSize: f32 = 0.0;

pub const ShapeProps = struct {
    // f32 instead of u8 because Uniforms in wgsl doesn't support u8 anyway
    fill_color: [4]f32 = .{ 1.0, 1.0, 1.0, 1.0 }, // Default fill color (red)
    stroke_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default stroke color (green)
    stroke_width: f32 = 2.0, // Default stroke width
};

pub const TextureCache = struct {
    id: u32,
    width: f32 = 0.0,
    height: f32 = 0.0,
    valid: bool = false, // false -> render bezier curves, not texture
    // once we finish editing shape ,we can render curves to texture and update valid = true
};

const DEFAULT_BOUNDS = [4]PointUV{
    .{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
    .{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
    .{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
    .{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
};

fn get_bounds_matrix(bounds: [4]PointUV) Matrix3x3 {
    const angle = bounds[0].angleTo(bounds[1]);
    const rotation = Matrix3x3.rotation(angle); // transfor matrix
    const scale = Matrix3x3.scaling(
        bounds[3].x - bounds[1].x,
        bounds[3].y - bounds[1].y,
    );
    const translate = Matrix3x3.translation(
        bounds[3].x,
        bounds[3].y,
    );

    const matrix = Matrix3x3.multiply(
        Matrix3x3.multiply(translate, scale),
        rotation,
    );

    return matrix;
}

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: ShapeProps,
    bounds: [4]PointUV,
    // last_bounds: [4]PointUV, // Used to detect changes in bounds
    cache: TextureCache,

    // Arrays: Use &array to get a slice reference
    // Slices: Pass directly (they're already slices)
    // ArrayList: Use .items to get the underlying slice
    pub fn new(id: u32, input_paths: []const []const Point, input_bounds: ?[4]PointUV, props: ShapeProps, cache: TextureCache, allocator: std.mem.Allocator) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);
        const bounds = input_bounds orelse DEFAULT_BOUNDS;
        const matrix = get_bounds_matrix(bounds);

        for (input_paths) |input_path| {
            // Create a mutable copy of the current path
            const mutable_path = try allocator.dupe(Point, input_path);
            defer allocator.free(mutable_path);

            for (mutable_path) |*point| {
                if (!Path.isStraightLineHandle(point.*)) {
                    const relative_point = matrix.transformPoint(point.*);
                    point.x = relative_point.x;
                    point.y = relative_point.y;
                }
            }

            const path = try Path.newFromPoints(mutable_path, POINT_SNAP_DISTANCE, allocator);
            try paths_list.append(path);
        }

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .cache = cache,
            .bounds = bounds,
        };

        return shape;
    }

    fn getRelativePoint(self: *Shape, point: Point) Point {
        const angle = self.bounds[0].angleTo(self.bounds[1]);
        const distance = self.bounds[0].distance(Point{
            .x = point.x - self.bounds[0].x,
            .y = point.y - self.bounds[0].y,
        });
        const relative_point = Point{
            .x = @sin(-angle) * distance,
            .y = @cos(-angle) * distance,
        };
        return relative_point;
    }

    pub fn addPointStart(
        self: *Shape,
        allocator: std.mem.Allocator,
        absolute_point: Point,
        option_active_path_index: ?usize,
    ) !usize {
        self.cache.valid = false;
        const matrix = get_bounds_matrix(self.bounds).inverse();
        const point = matrix.transformPoint(absolute_point);
        const close_path_threshold = matrix.transformPoint(Point{
            .x = POINT_SNAP_DISTANCE,
            .y = 0.0,
        }).length();

        if (option_active_path_index) |active_path_index| {
            var active_path = &self.paths.items[active_path_index];
            try active_path.addPoint(point, close_path_threshold);
            return active_path_index;
        } else {
            std.debug.print("adding new path - YEAH\n", .{});
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            return self.paths.items.len - 1;
        }
    }

    pub fn updateLastHandle(self: *Shape, active_path_index: usize, preview_point: Point) void {
        const matrix = get_bounds_matrix(self.bounds);
        const point = matrix.inverse().transformPoint(preview_point);

        const active_path = &self.paths.items[active_path_index];
        active_path.updateLastHandle(point);
        self.cache.valid = false;
    }

    // returns boolean indicating if texture size was updated or not
    pub fn updateTextureSize(self: *Shape) bool {
        const cache = &self.cache;

        const width = self.bounds[0].distance(self.bounds[1]);
        const height = self.bounds[0].distance(self.bounds[3]);
        const new_width = @min(Utils.getNextPowerOfTwo(@max(cache.width, width / shared.render_scale)), maxTextureSize);
        const new_height = @min(Utils.getNextPowerOfTwo(@max(cache.height, height / shared.render_scale)), maxTextureSize);

        if (cache.width >= new_width - EPSILON and cache.height >= new_height - EPSILON) {
            return false;
        }

        cache.width = new_width;
        cache.height = new_height;

        return true;
    }

    // instead of "force" we can integrate updateTextureSize here somehow I guess, or create a new method
    pub fn drawTextureCache(self: *Shape, allocator: std.mem.Allocator) !void {
        std.debug.print("Shape.drawTextureCache: cache valid: {}\n", .{self.cache.valid});
        // // try to avoid undefined
        // if (self.cache) |_cache| {
        //     if (_cache.valid and !force) return; // texture is up to date
        //     cache = _cache;
        //     texture_id = _cache.id;
        // } else {
        //     cache = TextureCache{
        //         .id = undefined,
        //         .points = undefined,
        //         .width = 0.0,
        //         .height = 0.0,
        //     };
        // }

        const option_vertex_output = try self.getDrawVertexData(
            allocator,
            null,
            null,
        );

        if (option_vertex_output) |vertex_output| {
            const left_bottom = vertex_output.bounding_box[0];
            const right_top = vertex_output.bounding_box[2];
            self.bounds = [4]PointUV{
                .{ .x = left_bottom.x, .y = right_top.y, .u = 0.0, .v = 1.0 },
                .{ .x = right_top.x, .y = right_top.y, .u = 1.0, .v = 1.0 },
                .{ .x = right_top.x, .y = left_bottom.y, .u = 1.0, .v = 0.0 },
                .{ .x = left_bottom.x, .y = left_bottom.y, .u = 0.0, .v = 0.0 },
            };

            if (self.cache.width <= EPSILON) {
                std.debug.print("Init cache texture size\n", .{});
                // we need to calculate bounding box first(we did this above) to set initial size
                _ = self.updateTextureSize();
            }

            const cache_bounding_box = bounding_box.BoundingBox{
                .min_x = left_bottom.x,
                .min_y = left_bottom.y,
                .max_x = right_top.x,
                .max_y = right_top.y,
            };

            update_texture_cache(
                self.cache.id,
                cache_bounding_box,
                vertex_output,
                self.cache.width,
                self.cache.height,
            );

            self.cache.valid = true;
        }
    }

    pub fn getSkeletonDrawVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
        preview_point: ?Point,
        is_handle_preview: bool,
    ) ![]triangles.DrawInstance {
        const matrix = get_bounds_matrix(self.bounds);

        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        for (self.paths.items) |path| {
            const path_skeleton = try path.getSkeletonDrawVertexData(matrix, allocator);
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

    pub fn getDrawVertexData(self: Shape, allocator: std.mem.Allocator, active_path_index: ?usize, option_preview_point: ?Point) !?DrawVertexOutput {
        const matrix = get_bounds_matrix(self.bounds);
        var curves_buffer = std.ArrayList(Point).init(allocator);

        for (self.paths.items, 0..) |path, i| {
            const preview_point = if (active_path_index == i)
                if (option_preview_point) |point| matrix.transformPoint(point) else null
            else
                null;

            const option_curve = try path.getDrawVertexData(allocator, preview_point);
            if (option_curve) |curve| {
                for (curve) |point| {
                    if (Path.isStraightLineHandle(point)) {
                        try curves_buffer.append(point);
                    } else {
                        try curves_buffer.append(matrix.transformPoint(point));
                    }
                }
                // try curves_buffer.appendSlice(curve);
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
            self.bounds[0],
            self.bounds[1],
            self.bounds[2],
            // second triangle
            self.bounds[2],
            self.bounds[3],
            self.bounds[0],
        };
    }

    pub fn getCacheTexturePickVertexData(self: Shape) [6]images.PickVertex {
        return [_]images.PickVertex{
            // first triangle
            .{ .id = self.id, .point = self.bounds[0] },
            .{ .id = self.id, .point = self.bounds[1] },
            .{ .id = self.id, .point = self.bounds[2] },
            // second triangle
            .{ .id = self.id, .point = self.bounds[2] },
            .{ .id = self.id, .point = self.bounds[3] },
            .{ .id = self.id, .point = self.bounds[0] },
        };
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
            .bounds = self.bounds,
            .cache = self.cache,
        };
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

pub const Serialized = struct {
    id: u32,
    paths: []const []const Point,
    props: ShapeProps,
    bounds: [4]PointUV,
    cache: ?TextureCache,

    pub fn compare(self: Serialized, other: Serialized) bool {

        // There is a problem with cache!!!!!
        // What if out previous version claims the cache is smaller then it actually is!!!!???
        // I don't like that cache is triggered in such a weird way right now, instead of during the render

        // in JS, we should compare size vs texture size, if texture is to small then request zig to give Shape vertex and render to texture
        // this way we can totally avoid whole zig texture logic!!!! So nothing to impact history!
        // but how will we handle when a new texture need to be generated??
        const all_match = self.id == other.id and
            self.paths.len == other.paths.len and
            std.meta.eql(self.props, other.props);
        // and std.meta.eql(self.bounds, other.bounds);

        if (!all_match) {
            return false;
        }

        for (self.paths, other.paths) |path_a, path_b| {
            if (path_a.len != path_b.len) {
                return false;
            }
            if (!std.meta.eql(path_a, path_b)) {
                return false;
            }
        }

        return true;
    }
};
