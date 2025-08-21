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
    stroke_width: f32 = 0.0, // Default stroke width
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
    // const angle = bounds[0].angleTo(bounds[1]);
    // const rotation = Matrix3x3.rotation(angle); // transfor matrix

    const scale = Matrix3x3.scaling(
        bounds[1].x - bounds[3].x,
        bounds[1].y - bounds[3].y,
    );
    const translate = Matrix3x3.translation(
        bounds[3].x,
        bounds[3].y,
    );
    return Matrix3x3.multiply(translate, scale);
    // std.debug.print("angle: {d}\n", .{angle});
    // std.debug.print("translate: {d}, {d}\n", .{ bounds[3].x, bounds[3].y });

    // const matrix = Matrix3x3.multiply(
    //     // translate,
    //     Matrix3x3.multiply(translate, scale),
    //     rotation,
    // );

    // return matrix;
}

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: ShapeProps,
    bounds: [4]PointUV,
    outdated_sdf: bool, // if true, we need to recalculate SDF
    cache: TextureCache,

    pub fn new(
        id: u32,
        input_paths: []const []const Point,
        bounds: ?[4]PointUV,
        props: ShapeProps,
        cache: TextureCache,
        allocator: std.mem.Allocator,
    ) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(
                input_path,
                POINT_SNAP_DISTANCE,
                allocator,
            );
            try paths_list.append(path);
        }

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .cache = cache,
            .outdated_sdf = false,
            .bounds = bounds orelse DEFAULT_BOUNDS, // will be updated later
        };

        // const from_svg_file = bounds == null and input_paths.len > 0;
        // if (from_svg_file) {
        //     const box = bounding_box.getBoundingBox(
        //         try shape.getAllPoints(allocator, 0, null),
        //         props.stroke_width / 2.0,
        //     );
        //     shape.bounds = [4]PointUV{
        //         .{ .x = box.min_x, .y = box.max_y, .u = 0.0, .v = 1.0 },
        //         .{ .x = box.max_x, .y = box.max_y, .u = 1.0, .v = 1.0 },
        //         .{ .x = box.max_x, .y = box.min_y, .u = 1.0, .v = 0.0 },
        //         .{ .x = box.min_x, .y = box.min_y, .u = 0.0, .v = 0.0 },
        //     };
        // }

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
        if (self.paths.items.len == 0) {
            self.bounds = [4]PointUV{
                .{ .x = absolute_point.x, .y = absolute_point.y + 1.0, .u = 0.0, .v = 1.0 },
                .{ .x = absolute_point.x + 1.0, .y = absolute_point.y + 1.0, .u = 1.0, .v = 1.0 },
                .{ .x = absolute_point.x + 1.0, .y = absolute_point.y, .u = 1.0, .v = 0.0 },
                .{ .x = absolute_point.x, .y = absolute_point.y, .u = 0.0, .v = 0.0 },
            };
            std.debug.print("bounds: {d}, {d}\n", .{ self.bounds[3].x, self.bounds[3].y });
            const new_path = try Path.new(.{ .x = 0.0, .y = 0.0 }, allocator);
            try self.paths.append(new_path);
            return 0;
        }
        // const norm_bounds = get_norm_bounds(self.bounds);

        self.outdated_sdf = true;
        std.debug.print("============addPointStart=============\n", .{});
        std.debug.print("bounds start: {d}, {d}\n", .{ self.bounds[3].x, self.bounds[3].y });
        std.debug.print("bounds end: {d}, {d}\n", .{ self.bounds[1].x, self.bounds[1].y });
        const matrix = get_bounds_matrix(self.bounds);
        std.debug.print("matrix: {any}\n", .{matrix});
        const invert_matrix = matrix.inverse();
        std.debug.print("invert_matrix: {any}\n", .{invert_matrix});
        std.debug.print("absolute point: {d}, {d}\n", .{ absolute_point.x, absolute_point.y });
        const point = invert_matrix.get(absolute_point);
        std.debug.print("point: {d}, {d}\n", .{ point.x, point.y });
        const close_path_threshold = invert_matrix.get(Point{
            .x = POINT_SNAP_DISTANCE,
            .y = 0.0,
        }).length();

        const updated_active_path_index = if (option_active_path_index) |active_path_index| blk: {
            var active_path = &self.paths.items[active_path_index];
            try active_path.addPoint(point, close_path_threshold);

            // const is_outside = point.x < self.bounds.min_x or point.x > self.bounds.max_x or point.y < self.bounds.min_y or point.y > self.bounds.max_y;
            // if (is_outside) {

            break :blk active_path_index;
        } else blk: {

            // we dont recalculate bounding box here because there is just one point,
            // so it cover 0 pixels
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            break :blk self.paths.items.len - 1;
        };

        // const points = try self.getAllPoints(allocator, null, null);
        try self.update_bounds(allocator);

        return updated_active_path_index;
    }

    fn update_bounds(self: *Shape, allocator: std.mem.Allocator) !void {
        const matrix = get_bounds_matrix(self.bounds);
        const invert_matrix = matrix.inverse();
        const points = try self.getAllPoints(allocator, 0, null);
        const box = bounding_box.getBoundingBox(points, self.props.stroke_width / 2.0);

        const old_box_end = invert_matrix.get(self.bounds[1]); // 0, 0
        const old_box_start = invert_matrix.get(self.bounds[3]); // 0, 0
        const curr_width = old_box_end.x - old_box_start.x; // 272
        const curr_height = old_box_end.y - old_box_start.y; // 269s

        const new_width = box.max_x - box.min_x; // 272
        const new_height = box.max_y - box.min_y; // 269s

        if (new_width <= EPSILON or new_height <= EPSILON) {
            return; // No valid bounding box
        }

        var points_list = std.ArrayList(Point).init(allocator);
        for (self.paths.items) |*path| {
            for (path.points.items) |*p| {
                if (Path.isStraightLineHandle(p.*)) {
                    try points_list.append(p.*);
                    continue; // we don't want to update straight line handlers
                }

                const curr_p = Point{
                    .x = old_box_start.x + p.x * curr_width,
                    .y = old_box_start.y + p.y * curr_height,
                };
                p.x = (curr_p.x - box.min_x) / new_width;
                p.y = (curr_p.y - box.min_y) / new_height;

                try points_list.append(p.*);
            }
        }

        self.bounds = [4]PointUV{
            matrix.getUV(.{ .x = box.min_x, .y = box.max_y, .u = 0.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.max_y, .u = 1.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.min_y, .u = 1.0, .v = 0.0 }),
            matrix.getUV(.{ .x = box.min_x, .y = box.min_y, .u = 0.0, .v = 0.0 }),
        };
    }

    fn get_bounds_preview(self: *Shape, allocator: std.mem.Allocator, points: []Point) ![]Point {
        const matrix = get_bounds_matrix(self.bounds);
        const invert_matrix = matrix.inverse();
        const old_box_end = invert_matrix.get(self.bounds[1]); // 0, 0
        const old_box_start = invert_matrix.get(self.bounds[3]); // 0, 0

        const box = bounding_box.getBoundingBox(points, self.props.stroke_width / 2.0);

        const width = box.max_x - box.min_x; // 272
        const height = box.max_y - box.min_y; // 269s

        if (width <= EPSILON or height <= EPSILON) {
            return points; // No valid bounding box, return original points
        }

        var points_list = std.ArrayList(Point).init(allocator);
        for (self.paths.items) |*path| {
            for (path.points.items) |*p| {
                if (Path.isStraightLineHandle(p.*)) {
                    try points_list.append(p.*);
                    continue; // we don't want to update straight line handlers
                }

                const curr_p = Point{
                    .x = old_box_start.x + p.x * (old_box_end.x - old_box_start.x),
                    .y = old_box_start.y + p.y * (old_box_end.y - old_box_start.y),
                };
                p.x = (curr_p.x - box.min_x) / width;
                p.y = (curr_p.y - box.min_y) / height;

                try points_list.append(p.*);
            }
        }

        self.bounds = [4]PointUV{
            matrix.getUV(.{ .x = box.min_x, .y = box.max_y, .u = 0.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.max_y, .u = 1.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.min_y, .u = 1.0, .v = 0.0 }),
            matrix.getUV(.{ .x = box.min_x, .y = box.min_y, .u = 0.0, .v = 0.0 }),
        };

        return try points_list.toOwnedSlice();
    }

    pub fn updateLastHandle(self: *Shape, allocator: std.mem.Allocator, active_path_index: usize, preview_point: Point) !void {
        const matrix = get_bounds_matrix(self.bounds);
        const point = matrix.inverse().get(preview_point);

        const active_path = &self.paths.items[active_path_index];
        active_path.updateLastHandle(point);

        self.outdated_sdf = true;
        try self.update_bounds(allocator);
    }

    // returns boolean indicating if texture size was updated or not
    // pub fn updateTextureSize(self: *Shape) bool {
    //     const cache = &self.cache;

    //     const width = self.bounds[0].distance(self.bounds[1]);
    //     const height = self.bounds[0].distance(self.bounds[3]);
    //     const new_width = @min(Utils.getNextPowerOfTwo(@max(cache.width, width / shared.render_scale)), maxTextureSize);
    //     const new_height = @min(Utils.getNextPowerOfTwo(@max(cache.height, height / shared.render_scale)), maxTextureSize);

    //     if (cache.width >= new_width - EPSILON and cache.height >= new_height - EPSILON) {
    //         return false;
    //     }

    //     cache.width = new_width;
    //     cache.height = new_height;

    //     return true;
    // }

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
            // self.bounds = [4]PointUV{
            //     .{ .x = left_bottom.x, .y = right_top.y, .u = 0.0, .v = 1.0 },
            //     .{ .x = right_top.x, .y = right_top.y, .u = 1.0, .v = 1.0 },
            //     .{ .x = right_top.x, .y = left_bottom.y, .u = 1.0, .v = 0.0 },
            //     .{ .x = left_bottom.x, .y = left_bottom.y, .u = 0.0, .v = 0.0 },
            // };

            if (self.cache.width <= EPSILON) {
                std.debug.print("Init cache texture size\n", .{});
                // we need to calculate bounding box first(we did this above) to set initial size
                // _ = self.updateTextureSize();
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

            self.outdated_sdf = false;
        }
    }

    pub fn getSkeletonDrawVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
        preview_point: ?Point,
        is_handle_preview: bool,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const matrix = get_bounds_matrix(self.bounds);

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

    fn getAllPoints(
        self: Shape,
        allocator: std.mem.Allocator,
        active_path_index: ?usize,
        option_preview_point: ?Point,
    ) ![]Point {
        var points = std.ArrayList(Point).init(allocator);
        for (self.paths.items, 0..) |path, i| {
            var preview_point: ?Point = null;

            if (active_path_index == i) {
                if (option_preview_point) |point| {
                    const inverted_matrix = get_bounds_matrix(self.bounds).inverse();
                    preview_point = inverted_matrix.get(point);
                }
            }

            if (try path.getDrawVertexData(allocator, preview_point)) |closed_path| {
                points.appendSlice(closed_path) catch unreachable;
            }
        }

        return points.toOwnedSlice();
    }

    pub fn getDrawVertexData(self: *Shape, allocator: std.mem.Allocator, active_path_index: ?usize, option_preview_point: ?Point) !?DrawVertexOutput {
        const points = try self.getAllPoints(allocator, active_path_index, option_preview_point);

        // const points = try self.update_bounds(allocator, before_points);
        // std.debug.print("first bounds: {d}, {d}\n", .{ self.bounds[0].x, self.bounds[0].y });
        // const matrix = get_bounds_matrix(self.bounds);
        const scale = Matrix3x3.scaling(
            self.bounds[1].x - self.bounds[3].x,
            self.bounds[1].y - self.bounds[3].y,
        );
        // const unscaled_matrix = matrix.scale(
        //     1.0 / scale.x,
        //     1.0 / scale.y,
        // );
        // std.debug.print("BEFORE: first point: {d}, {d}\n", .{ points[0].x, points[0].y });
        for (points) |*point| {
            // Transform points to the bounding box space
            point.x = scale.get(point).x;
            point.y = scale.get(point).y;
        }
        // std.debug.print("AFTER: first point: {d}, {d}\n", .{ points[0].x, points[0].y });
        // if (option_preview_point) |point| {
        //     const is_outside = point.x < self.bounds.min_x or point.x > self.bounds.max_x or point.y < self.bounds.min_y or point.y > self.bounds.max_y;
        //     if (is_outside) {
        //         self.bounds = bounding_box.getBoundingBox(points, self.props.stroke_width / 2.0);
        //     }
        // }
        // self.bounds = get_bounds_matrix(self.bounds)

        if (points.len > 0) {
            // Shape.prepare_half_straight_lines(curves);
            // std.debug.print("self.bounds first point: {d}, {d}\n", .{ self.bounds[3].x, self.bounds[3].y });
            const box_vertex = [6]PointUV{
                // First triangle
                scale.getUV(PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 }),
                scale.getUV(PointUV{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 }),
                scale.getUV(PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 }),
                // Second triangle
                scale.getUV(PointUV{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 }),
                scale.getUV(PointUV{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 }),
                scale.getUV(PointUV{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 }),
            };

            return DrawVertexOutput{
                .curves = points, // Transfer ownership directly
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

    pub fn getCacheTexturePickVertexData(self: Shape) PickVertexOutput {
        const bounds = [_]images.PickVertex{
            // first triangle
            .{ .id = self.id, .point = self.bounds[0] },
            .{ .id = self.id, .point = self.bounds[1] },
            .{ .id = self.id, .point = self.bounds[2] },
            // second triangle
            .{ .id = self.id, .point = self.bounds[2] },
            .{ .id = self.id, .point = self.bounds[3] },
            .{ .id = self.id, .point = self.bounds[0] },
        };

        return PickVertexOutput{
            .bounds = bounds,
            .uniforms = Uniform{
                .stroke_width = self.props.stroke_width,
                .fill_color = self.props.fill_color,
                .stroke_color = self.props.stroke_color,
            },
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
    bounding_box: [6]PointUV,
    uniform: Uniform,
};

pub const Uniform = extern struct {
    stroke_width: f32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // Padding for alignment
    fill_color: [4]f32,
    stroke_color: [4]f32,
};

const PickVertexOutput = struct { bounds: [6]images.PickVertex, uniforms: Uniform };

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
            std.meta.eql(self.props, other.props); // and
        // std.meta.eql(self.bounds, other.bounds);

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
