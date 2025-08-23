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

var active_path_index: ?usize = null;
var is_handle_preview: bool = false;
var preview_point: ?Point = null;

pub fn resetState() void {
    active_path_index = null;
    is_handle_preview = false;
    preview_point = null;
}

pub fn onReleasePointer() void {
    is_handle_preview = false;
}

pub const ShapeProps = struct {
    // f32 instead of u8 because Uniforms in wgsl doesn't support u8 anyway
    fill_color: [4]f32 = .{ 1.0, 0.0, 0.0, 1.0 }, // Default fill color (red)
    stroke_color: [4]f32 = .{ 0.9, 0.9, 0.0, 1.0 }, // Default stroke color (green)
    stroke_width: f32 = 20.0, // Default stroke width
};

pub const TextureCache = struct {
    id: u32,
    width: f32 = 0.0,
    height: f32 = 0.0,
    valid: bool = false, // false -> render bezier curves, not texture
    // once we finish editing shape ,we can render curves to texture and update valid = true
};

pub const Preview = struct {
    index: usize,
    point: Point,
};

const DEFAULT_BOUNDS = [4]PointUV{
    .{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
    .{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
    .{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
    .{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
};

pub fn getSkeletonUniform() Uniform {
    return Uniform{
        .stroke_width = 2.0 * shared.render_scale,
        .fill_color = .{ 0.0, 0.0, 0.0, 0.0 },
        .stroke_color = .{ 0.0, 0.0, 1.0, 1.0 },
    };
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
        input_bounds: ?[4]PointUV,
        props: ShapeProps,
        cache: TextureCache,
        allocator: std.mem.Allocator,
    ) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        const bounds = input_bounds orelse DEFAULT_BOUNDS;
        const invert_matrix = Matrix3x3.getMatrixFromRectangle(bounds).inverse();
        const close_path_threshold = Point{
            .x = POINT_SNAP_DISTANCE * @abs(invert_matrix.values[0]),
            .y = POINT_SNAP_DISTANCE * @abs(invert_matrix.values[4]),
        };

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(
                input_path,
                close_path_threshold,
                allocator,
            );
            try paths_list.append(path);
        }
        var shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .cache = cache,
            .outdated_sdf = false,
            .bounds = bounds,
        };

        const from_svg_file = input_bounds == null and input_paths.len > 0;
        if (from_svg_file) {
            try shape.update_bounds(allocator, null);
        }

        return shape;
    }

    pub fn addPointStart(
        self: *Shape,
        allocator: std.mem.Allocator,
        absolute_point: Point,
    ) !void {
        is_handle_preview = true;

        if (self.paths.items.len == 0) {
            self.bounds = [4]PointUV{
                .{ .x = absolute_point.x, .y = absolute_point.y + 1.0, .u = 0.0, .v = 1.0 },
                .{ .x = absolute_point.x + 1.0, .y = absolute_point.y + 1.0, .u = 1.0, .v = 1.0 },
                .{ .x = absolute_point.x + 1.0, .y = absolute_point.y, .u = 1.0, .v = 0.0 },
                .{ .x = absolute_point.x, .y = absolute_point.y, .u = 0.0, .v = 0.0 },
            };

            const new_path = try Path.new(.{ .x = 0.0, .y = 0.0 }, allocator);
            try self.paths.append(new_path);
            active_path_index = 0;
            return;
        }

        self.outdated_sdf = true;

        const invert_matrix = Matrix3x3.getMatrixFromRectangle(self.bounds).inverse();
        const point = invert_matrix.get(absolute_point);

        const close_path_threshold = Point{
            .x = POINT_SNAP_DISTANCE * @abs(invert_matrix.values[0]),
            .y = POINT_SNAP_DISTANCE * @abs(invert_matrix.values[4]),
        }; // TODO: are we sure this gonna work? What if scale is negative?

        if (active_path_index) |i| {
            var active_path = &self.paths.items[i];
            if (!active_path.closed) {
                try active_path.addPoint(point, close_path_threshold);
                try self.update_bounds(allocator, null);
                return;
            }
        }

        // start a new path
        const new_path = try Path.new(point, allocator);
        try self.paths.append(new_path);
        active_path_index = self.paths.items.len - 1;
        try self.update_bounds(allocator, null);
    }

    pub fn updatePointPreview(self: *Shape, x: f32, y: f32) !void {
        const p = Point{ .x = x, .y = y };
        if (is_handle_preview) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            try self.updateLastHandle(
                allocator,
                p,
            );
        } else {
            preview_point = p;
        }
    }

    fn update_bounds(self: *Shape, allocator: std.mem.Allocator, option_preview_point: ?Point) !void {
        const points = try self.getAllPoints(
            allocator,
            option_preview_point,
            active_path_index,
        );
        const box = bounding_box.getBoundingBox(points);

        const new_width = box.max_x - box.min_x;
        const new_height = box.max_y - box.min_y;

        if (Utils.cmpF32(new_width, 0) or Utils.cmpF32(new_height, 0)) {
            return; // No valid bounding box
        }

        // Normalize points to [0,1] range
        for (self.paths.items) |*path| {
            for (path.points.items) |*p| {
                if (Path.isStraightLineHandle(p.*)) continue;

                p.x = (p.x - box.min_x) / new_width;
                p.y = (p.y - box.min_y) / new_height;
            }
        }

        const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);
        self.bounds = [4]PointUV{
            matrix.getUV(.{ .x = box.min_x, .y = box.max_y, .u = 0.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.max_y, .u = 1.0, .v = 1.0 }),
            matrix.getUV(.{ .x = box.max_x, .y = box.min_y, .u = 1.0, .v = 0.0 }),
            matrix.getUV(.{ .x = box.min_x, .y = box.min_y, .u = 0.0, .v = 0.0 }),
        };
    }

    fn updateLastHandle(self: *Shape, allocator: std.mem.Allocator, absolute_point: Point) !void {
        if (active_path_index) |i| {
            const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);
            const point = matrix.inverse().get(absolute_point);

            const active_path = &self.paths.items[i];
            active_path.updateLastHandle(point);

            self.outdated_sdf = true;
            try self.update_bounds(allocator, null);
        }
    }

    pub fn getSkeletonDrawVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);

        for (self.paths.items) |path| {
            const path_skeleton = try path.getSkeletonDrawVertexData(matrix, allocator);
            try skeleton_buffer.appendSlice(path_skeleton);
        }

        if (preview_point) |point| {
            if (!is_handle_preview) {
                const buffer = Path.getVertexSkeletonPoint(true, point);
                try skeleton_buffer.appendSlice(&buffer);
            }
        }

        return skeleton_buffer.toOwnedSlice();
    }

    fn getAllPoints(
        self: Shape,
        allocator: std.mem.Allocator,
        option_preview_point: ?Point,
        option_preview_index: ?usize,
    ) ![]Point {
        var points = std.ArrayList(Point).init(allocator);
        for (self.paths.items, 0..) |path, i| {
            var preview_p: ?Point = null;

            if (option_preview_point) |p| {
                if (option_preview_index) |idx| {
                    if (idx == i) {
                        const inverted_matrix = Matrix3x3.getMatrixFromRectangle(self.bounds).inverse();
                        preview_p = inverted_matrix.get(p);
                    }
                }
            }

            if (try path.getDrawVertexData(allocator, preview_p)) |closed_path| {
                points.appendSlice(closed_path) catch unreachable;
            }
        }

        return points.toOwnedSlice();
    }

    pub fn getUniform(self: Shape) Uniform {
        return Uniform{
            .stroke_width = self.props.stroke_width,
            .fill_color = self.props.fill_color,
            .stroke_color = self.props.stroke_color,
        };
    }

    pub fn getDrawVertexData(self: *Shape, allocator: std.mem.Allocator) !?[]Point {
        if (active_path_index != null and preview_point != null) {
            try self.update_bounds(allocator, preview_point);
        }

        const points = try self.getAllPoints(
            allocator,
            preview_point,
            active_path_index,
        );

        if (points.len == 0) {
            return null;
        }

        const scale = Matrix3x3.scaling(
            self.bounds[0].distance(self.bounds[1]),
            self.bounds[0].distance(self.bounds[3]),
        );

        const padding = self.props.stroke_width / 2.0;
        for (points) |*point| {
            const scaled = scale.get(point);
            point.x = padding + scaled.x;
            point.y = padding + scaled.y;
        }

        return points;
    }

    pub fn getBoundsWithPadding(self: Shape) [4]PointUV {
        const padding = self.props.stroke_width / 2.0;
        var buffer: [4]PointUV = undefined;
        const len = self.bounds.len;

        for (self.bounds, 0..) |b, i| {
            const b_next = self.bounds[(i + 1) % len];
            const b_prev = self.bounds[@min((i -% 1), (len - 1)) % len];

            const angle_next = b.angleTo(b_next);
            const angle_prev = b.angleTo(b_prev);

            buffer[i] = b;
            buffer[i].x -= @cos(angle_next) * padding + @cos(angle_prev) * padding;
            buffer[i].y -= @sin(angle_next) * padding + @sin(angle_prev) * padding;
        }

        return buffer;
    }

    pub fn getDrawBounds(self: Shape) [6]PointUV {
        const bounds = self.getBoundsWithPadding();
        return [_]PointUV{
            // first triangle
            bounds[0],
            bounds[1],
            bounds[2],
            // second triangle
            bounds[2],
            bounds[3],
            bounds[0],
        };
    }

    pub fn getPickBounds(self: Shape) [6]images.PickVertex {
        const bounds = self.getDrawBounds();
        var buffer: [6]images.PickVertex = undefined;
        for (bounds, 0..) |b, i| {
            buffer[i] = .{
                .point = b,
                .id = self.id,
            };
        }
        return buffer;
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
