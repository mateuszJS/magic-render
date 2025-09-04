const Utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const TextureSize = @import("../texture_size.zig").TextureSize;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");
const lines = @import("../lines.zig");
const Path = @import("paths.zig").Path;
const shared = @import("../shared.zig");
const images = @import("../images.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const DEFAULT_BOUNDS = @import("../consts.zig").DEFAULT_BOUNDS;
const PackedId = @import("packed_id.zig");
const PathUtils = @import("path_utils.zig");
const fill = @import("fill.zig");

const EPSILON = std.math.floatEps(f32);
const CREATE_HANDLE_THRESHOLD = 10.0;
// above this distance two handles are created around control point
// below that distance, handle is a straight line handle

// this state is not included in the shape struct only because there is no need, methods which uses these variables
// are called only when shape is selected, so only one active shape/path uses them
var active_path_index: ?usize = null;
var is_handle_preview: bool = false;
pub var selected_point_id: ?PackedId.PointId = null;

pub fn resetState() void {
    active_path_index = null;
    is_handle_preview = false;
    selected_point_id = null;
}

pub const Preview = struct {
    index: usize,
    point: Point,
};

fn getSnapThreshold(bounds: [4]PointUV) Point {
    const invert_matrix = Matrix3x3.getMatrixFromRectangle(bounds).inverse();
    const close_path_threshold = Point{
        .x = 10.0 * @abs(invert_matrix.values[0]),
        .y = 10.0 * @abs(invert_matrix.values[4]),
    };
    return close_path_threshold;
}

pub const Filter = struct {
    gaussianBlur: Point,
};

pub const Props = struct {
    fill: fill.Fill,
    stroke: fill.Fill,
    stroke_width: f32,
    filter: ?Filter,
};
pub const SerializedProps = struct {
    fill: fill.SerializedFill,
    stroke: fill.SerializedFill,
    stroke_width: f32,
    filter: ?Filter,
};

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: Props,
    bounds: [4]PointUV,

    sdf_scale: f32 = 1.0,
    outdated_sdf: bool, // if true, we need to recalculate SDF
    sdf_texture_id: u32,

    cache_texture_id: u32,
    outdated_cache: bool,

    preview_point: ?Point = null,

    sdf_size: TextureSize = .{ .w = 0, .h = 0 }, // stores the last size of computed sdf
    // useful only while updating scale to avoid unnecessary regenerations if size hasn't grown

    pub fn new(
        id: u32,
        input_paths: []const []const Point,
        input_bounds: ?[4]PointUV,
        input_props: SerializedProps,
        sdf_texture_id: u32,
        cache_texture_id: u32,
        allocator: std.mem.Allocator,
    ) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(
                input_path,
                allocator,
            );
            try paths_list.append(path);
        }

        const props = Props{
            .fill = try fill.Fill.new(input_props.fill, allocator),
            .stroke = try fill.Fill.new(input_props.stroke, allocator),
            .stroke_width = input_props.stroke_width,
            .filter = input_props.filter,
        };

        const shape = Shape{ .id = id, .paths = paths_list, .props = props, .sdf_texture_id = sdf_texture_id, .outdated_sdf = true, .bounds = input_bounds orelse DEFAULT_BOUNDS, .cache_texture_id = cache_texture_id, .outdated_cache = true };

        return shape;
    }

    pub fn addPointStart(
        self: *Shape,
        allocator: std.mem.Allocator,
        absolute_point: Point,
    ) !void {
        is_handle_preview = true;

        if (self.paths.items.len == 0) {
            for (&self.bounds, DEFAULT_BOUNDS) |*b, default| {
                b.* = default;
                b.x += absolute_point.x;
                b.y += absolute_point.y;
            }

            const new_path = try Path.new(.{ .x = 0.0, .y = 0.0 }, allocator);
            try self.paths.append(new_path);
            active_path_index = 0;
            return;
        }

        self.outdated_sdf = true;

        const invert_matrix = Matrix3x3.getMatrixFromRectangle(self.bounds).inverse();
        const point = invert_matrix.get(absolute_point);

        if (active_path_index) |i| {
            var active_path = &self.paths.items[i];
            try active_path.addPoint(point, getSnapThreshold(self.bounds));
        } else {
            // start a new path
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            active_path_index = self.paths.items.len - 1;
        }
    }

    pub fn updatePointPreview(self: *Shape, p: Point) void {
        if (is_handle_preview) {
            if (active_path_index) |index| {
                const path = self.paths.items[index];
                const points = path.points.items;
                const last_cp: Point = if (points.len == 2) points[0] else if (path.closed) points[0] else points[points.len - 1];
                const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);
                const dist = matrix.get(last_cp).distance(p);

                if (dist > CREATE_HANDLE_THRESHOLD) {
                    self.updateLastHandle(p);
                } else {
                    self.updateLastHandle(PathUtils.STRAIGHT_LINE_HANDLE);
                }
            }
        } else {
            self.update_preview_point(p);
        }
    }

    // the point of this method is to limit sets of outdated_sdf to true
    pub fn update_preview_point(self: *Shape, p: ?Point) void {
        if (active_path_index == null) {
            return;
        }

        const curr_preview = self.preview_point orelse Point{ .x = std.math.inf(f32), .y = 0 };
        const new_preview = p orelse Point{ .x = std.math.inf(f32), .y = 0 };

        const is_diff = !Utils.equalF32(curr_preview.x, new_preview.x) or !Utils.equalF32(curr_preview.y, new_preview.y);

        if (is_diff) {
            self.preview_point = p;
            self.outdated_sdf = true;
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

        if (Utils.equalF32(new_width, 0) or Utils.equalF32(new_height, 0)) {
            return; // No valid bounding box
        }

        // Normalize points to [0,1] range
        for (self.paths.items) |*path| {
            for (path.points.items) |*p| {
                if (PathUtils.isStraightLineHandle(p.*)) continue;
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

    fn updateLastHandle(self: *Shape, absolute_point: Point) void {
        if (active_path_index) |i| {
            const point = if (PathUtils.isStraightLineHandle(absolute_point)) b: {
                break :b absolute_point;
            } else b: {
                const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);
                break :b matrix.inverse().get(absolute_point);
            };

            const active_path = &self.paths.items[i];
            active_path.updateLastHandle(point);
            self.outdated_sdf = true;
        }
    }

    pub fn onReleasePointer(self: *Shape) void {
        if (active_path_index) |i| {
            const active_path = self.paths.items[i];
            if (active_path.closed) {
                active_path_index = null;
                self.preview_point = null;
            }
        }

        is_handle_preview = false;
    }

    pub fn getSkeletonDrawVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
        input_hover_id: ?PackedId.PointId,
        with_preview: bool,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);

        for (self.paths.items, 0..) |path, i| {
            const hover_id = if (input_hover_id) |h| if (h.path == i) h else null else null;
            const path_skeleton = try path.getSkeletonDrawVertexData(
                matrix,
                allocator,
                hover_id,
                with_preview,
            );
            try skeleton_buffer.appendSlice(path_skeleton);
        }

        if (self.preview_point) |point| {
            if (!is_handle_preview) {
                const buffer = PathUtils.getVertexDrawSkeletonPoint(true, point, false);
                try skeleton_buffer.appendSlice(&buffer);
            }
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getSkeletonUniform(self: Shape) Uniform {
        return Uniform{
            .solid = .{
                .stroke_width = PathUtils.SKELETON_LINE_WIDTH * self.sdf_scale * shared.render_scale,
                .fill_color = .{ 0.0, 0.0, 0.0, 0.0 },
                .stroke_color = .{ 0.0, 0.0, 1.0, 1.0 },
            },
        };
    }

    pub fn getSkeletonPickVertexData(
        self: Shape,
        allocator: std.mem.Allocator,
    ) ![]triangles.PickInstance {
        var skeleton_buffer = std.ArrayList(triangles.PickInstance).init(allocator);
        const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);

        for (self.paths.items, 0..) |path, i| {
            const path_skeleton = try path.getSkeletonPickVertexData(matrix, allocator, self.id, @as(u32, i));
            try skeleton_buffer.appendSlice(path_skeleton);
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

            try path.getClosedPathPoints(&points, preview_p);
        }

        PathUtils.prepareHalfStraightLines(points.items);

        return points.toOwnedSlice();
    }

    pub fn getStrokeWidth(self: Shape) f32 {
        return self.props.stroke_width * self.sdf_scale;
    }

    pub fn getUniform(self: Shape) Uniform {
        switch (self.props.fill) {
            .solid => |color| {
                return Uniform{
                    .solid = .{
                        .stroke_width = self.getStrokeWidth(),
                        .fill_color = color, //self.props.fill_color,
                        .stroke_color = .{ 0, 1, 0, 1 }, //self.props.stroke_color,
                    },
                };
            },
            .linear => |gradient| {
                var stops: [10]UniformGradientStop = undefined;
                for (gradient.stops.items, 0..) |stop, i| {
                    stops[i] = UniformGradientStop{
                        .offset = stop.offset,
                        .color = stop.color,
                    };
                }

                return Uniform{
                    .linear = .{
                        .stroke_width = self.getStrokeWidth(),
                        .stops_count = gradient.stops.items.len,
                        .start = gradient.start,
                        .end = gradient.end,
                        .stops = stops,
                    },
                };
            },
            .radial => |gradient| {
                var stops: [10]UniformGradientStop = undefined;
                for (gradient.stops.items, 0..) |stop, i| {
                    stops[i] = UniformGradientStop{
                        .offset = stop.offset,
                        .color = stop.color,
                    };
                }

                return Uniform{
                    .radial = .{
                        .stroke_width = self.getStrokeWidth(),
                        .stops_count = gradient.stops.items.len,
                        .center = gradient.center,
                        .destination = gradient.destination,
                        .stops = stops,
                        .radius_ratio = gradient.radius_ratio,
                    },
                };
            },
        }
    }

    pub fn getPadding(self: Shape) f32 {
        return self.props.stroke_width / 2.0;
    }

    // function has side effect, marks texture as generated
    pub fn getNewSdfPoint(self: *Shape, allocator: std.mem.Allocator) !?[]Point {
        if (!self.outdated_sdf) {
            @panic("getNewSdfPoint was called but the shape sdf was not marked as outdated!");
        }
        const check_points = try self.getAllPoints(
            allocator,
            self.preview_point,
            active_path_index,
        );
        if (check_points.len < 4) {
            return null;
        }

        try self.update_bounds(allocator, self.preview_point);

        const points = try self.getAllPoints(
            allocator,
            self.preview_point,
            active_path_index,
        );

        if (points.len == 0) {
            return null;
        }

        const scale = Matrix3x3.scaling(
            self.bounds[0].distance(self.bounds[1]),
            self.bounds[0].distance(self.bounds[3]),
        );

        const padding = self.getPadding();
        for (points) |*point| {
            const scaled = scale.get(point);
            point.x = padding + scaled.x;
            point.y = padding + scaled.y;
        }

        self.outdated_sdf = false;

        return points;
    }

    pub fn getBoundsWithPadding(self: Shape, scale: f32) [4]PointUV {
        const padding = self.getPadding();
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
            buffer[i].x *= scale;
            buffer[i].y *= scale;
        }

        return buffer;
    }

    pub fn getDrawBounds(self: Shape) [6]PointUV {
        const bounds = self.getBoundsWithPadding(1);
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
        const props = SerializedProps{
            .fill = self.props.fill.serialize(),
            .stroke = self.props.stroke.serialize(),
            .stroke_width = self.props.stroke_width,
            .filter = self.props.filter,
        };

        return Serialized{
            .id = self.id,
            .paths = try paths_list.toOwnedSlice(),
            .props = props,
            .bounds = self.bounds,
            .sdf_texture_id = self.sdf_texture_id,
            .cache_texture_id = self.cache_texture_id,
        };
    }

    pub fn deinit(self: *Shape) void {
        for (self.paths.items) |path| {
            path.deinit();
        }
        self.paths.deinit();
        self.props.stroke.deinit();
        self.props.fill.deinit();
    }
};

const UniformSolid = extern struct {
    stroke_width: f32,
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // Padding for alignment
    fill_color: [4]f32,
    stroke_color: [4]f32,
};

const UniformGradientStop = extern struct {
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    offset: f32 = 0.0,
    padding: [3]u32 = .{ 0, 0, 0 },
};

const UniformLinearGradient = extern struct {
    stroke_width: f32,
    stops_count: u32,
    padding: [2]f32 = .{ 0.0, 0.0 }, // Padding for alignment
    start: Point,
    end: Point,
    stops: [10]UniformGradientStop,
};

const UniformRadialGradient = extern struct {
    stroke_width: f32,
    stops_count: u32,
    radius_ratio: f32,
    padding: u32 = 0, // Padding for alignment
    center: Point,
    destination: Point, // rx, ry for elliptical gradients
    stops: [10]UniformGradientStop,
};

pub const Uniform = union(enum) {
    solid: UniformSolid,
    linear: UniformLinearGradient,
    radial: UniformRadialGradient,
};

pub const Serialized = struct {
    id: u32,
    paths: []const []const Point,
    props: SerializedProps,
    bounds: [4]PointUV,
    sdf_texture_id: u32,
    cache_texture_id: u32,

    // this function returns a lot of false positives because we compare floating point numbers
    pub fn compare(self: Serialized, other: Serialized) bool {

        // There is a problem with cache!!!!!
        // What if out previous version claims the cache is smaller then it actually is!!!!???
        // I don't like that cache is triggered in such a weird way right now, instead of during the render

        // in JS, we should compare size vs texture size, if texture is to small then request zig to give Shape vertex and render to texture
        // this way we can totally avoid whole zig texture logic!!!! So nothing to impact history!
        // but how will we handle when a new texture need to be generated??
        const all_match = self.id == other.id and
            self.paths.len == other.paths.len and
            std.meta.eql(self.props, other.props) and
            std.meta.eql(self.bounds, other.bounds);

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
