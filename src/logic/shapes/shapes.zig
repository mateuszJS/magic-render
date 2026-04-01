const utils = @import("../utils.zig");
const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const TextureSize = @import("../texture_size.zig").TextureSize;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangles.zig");
const lines = @import("../lines.zig");
const Path = @import("paths.zig").Path;
const shared = @import("../shared.zig");
const images = @import("../images.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const consts = @import("../consts.zig");
const path_utils = @import("path_utils.zig");
const fill = @import("../sdf/fill.zig");
const sdf_drawing = @import("../sdf/drawing.zig");
const AssetId = @import("../asset_id.zig").AssetId;
const asset_props = @import("../asset_props.zig");
const sdf_effect = @import("../sdf/effect.zig");

const CREATE_HANDLE_THRESHOLD = 10.0;
// above this distance two handles are created around control point
// below that distance, handle is a straight line handle

// this state is not included in the shape struct only because there is no need, methods which uses these variables
// are called only when shape is selected, so only one active shape/path uses them
var active_path_index: ?usize = null;
var is_handle_preview: bool = false;

pub fn resetState() void {
    active_path_index = null;
    is_handle_preview = false;
}

pub const Preview = struct {
    index: usize,
    point: Point,
};

fn getSnapThreshold(bounds: [4]PointUV) Point {
    const invert_matrix = Matrix3x3.getMatrixFromRectangle(bounds).inverse();
    const close_path_threshold = Point{
        .x = 20.0 * @abs(invert_matrix.values[0]),
        .y = 20.0 * @abs(invert_matrix.values[4]),
    };
    return close_path_threshold;
}

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: asset_props.Props,
    effects: std.ArrayList(sdf_effect.Effect),
    bounds: [4]PointUV,

    sdf_tex: sdf_drawing.SdfTex,

    should_update_sdf: bool, // throttled update,
    // less important than outdated_sdf which triggers instantly
    // this one triggers update on the next throttle event

    cache_scale: f32 = 1.0,
    outdated_cache: bool,
    cache_texture_id: ?u32,

    preview_point: ?Point = null,

    pub fn new(
        id: u32,
        input_paths: []const []const Point,
        input_bounds: [4]PointUV,
        props: asset_props.Props,
        input_effects: []const sdf_effect.Serialized,
        sdf_texture_id: u32,
        cache_texture_id: ?u32,
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

        var shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .effects = try sdf_effect.deserialize(input_effects, allocator),
            .sdf_tex = sdf_drawing.SdfTex{ .id = sdf_texture_id },
            .should_update_sdf = false,
            .bounds = input_bounds,
            .cache_texture_id = cache_texture_id,
            .outdated_cache = true,
        };

        // calculate bounds early so there won't be a change detected while serializing
        // between consts.DEFAULT_BOUNDS  vs real bounds(calculated below)
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        try shape.update_bounds(arena_allocator, null);

        return shape;
    }

    pub fn addPointStart(
        self: *Shape,
        allocator: std.mem.Allocator,
        absolute_point: Point,
    ) !void {
        is_handle_preview = true;

        if (self.paths.items.len == 0) {
            for (&self.bounds, consts.DEFAULT_BOUNDS) |*b, default| {
                b.* = default;
                b.x += absolute_point.x;
                b.y += absolute_point.y;
            }

            const new_path = try Path.new(.{ .x = 0.0, .y = 0.0 }, allocator);
            try self.paths.append(new_path);
            active_path_index = 0;
            return;
        }

        self.sdf_tex.is_outdated = true;

        const invert_matrix = Matrix3x3.getMatrixFromRectangle(self.bounds).inverse();
        const point = invert_matrix.get(absolute_point);

        if (active_path_index) |i| {
            var active_path = &self.paths.items[i];
            const is_closing = active_path.getIsClosing(point, getSnapThreshold(self.bounds)) != null;
            try active_path.addPoint(point, is_closing);
        } else {
            // start a new path
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            active_path_index = self.paths.items.len - 1;
        }
    }

    pub fn updatePointPreview(self: *Shape, p: Point) void {
        if (active_path_index) |index| {
            const path = self.paths.items[index];
            const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);

            if (is_handle_preview) {
                const points = path.points.items;
                const last_cp: Point = if (points.len == 2) points[0] else if (path.closed) points[0] else points[points.len - 1];

                const dist = matrix.get(last_cp).distance(p);

                if (dist > CREATE_HANDLE_THRESHOLD) {
                    self.updateLastHandle(p);
                } else {
                    self.updateLastHandle(path_utils.STRAIGHT_LINE_HANDLE);
                }
            } else {
                const relative_point = matrix.inverse().get(p);
                const is_closing_point = path.getIsClosing(relative_point, getSnapThreshold(self.bounds));
                const new_preview_point =
                    if (is_closing_point) |closing_p|
                        matrix.get(closing_p)
                    else
                        p;
                self.updateControlPointPreview(new_preview_point);
            }
        }
    }

    // the point of this method is to limit sets of outdated_sdf to true
    pub fn updateControlPointPreview(self: *Shape, p: ?Point) void {
        const curr_preview = self.preview_point orelse Point{ .x = std.math.inf(f32), .y = 0 };
        const new_preview = p orelse Point{ .x = std.math.inf(f32), .y = 0 };

        const is_diff = !utils.equalF32(curr_preview.x, new_preview.x) or !utils.equalF32(curr_preview.y, new_preview.y);

        if (is_diff) {
            self.preview_point = p;
            self.sdf_tex.is_outdated = true;
        }
    }

    pub fn update_bounds(self: *Shape, allocator: std.mem.Allocator, option_preview_point: ?Point) !void {
        const points = try self.getAllPoints(
            allocator,
            option_preview_point,
            active_path_index,
        );

        const box = bounding_box.getBoundingBox(points);

        const new_width = box.max_x - box.min_x;
        const new_height = box.max_y - box.min_y;

        if (utils.equalF32(new_width, 0) or utils.equalF32(new_height, 0)) {
            return; // No valid bounding box
        }

        // Normalize points to [0,1] range
        for (self.paths.items) |*path| {
            for (path.points.items) |*p| {
                if (path_utils.isStraightLineHandle(p.*)) continue;
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
            const point = if (path_utils.isStraightLineHandle(absolute_point)) b: {
                break :b absolute_point;
            } else b: {
                const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);
                break :b matrix.inverse().get(absolute_point);
            };

            const active_path = &self.paths.items[i];
            active_path.updateLastHandle(point);
            self.sdf_tex.is_outdated = true;
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
        option_hover_id: ?AssetId,
        with_preview: bool,
    ) ![]triangles.DrawInstance {
        var skeleton_buffer = std.ArrayList(triangles.DrawInstance).init(allocator);
        const matrix = Matrix3x3.getMatrixFromRectangle(self.bounds);

        for (self.paths.items, 0..) |path, i| {
            const hover_id = if (option_hover_id) |id| b: {
                break :b if (id.isSec() and id.getSec() == i) id else null;
            } else null;

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
                const buffer = path_utils.getVertexDrawSkeletonPoint(true, point, false);
                try skeleton_buffer.appendSlice(&buffer);
            }
        }

        return skeleton_buffer.toOwnedSlice();
    }

    pub fn getSkeletonUniform(self: Shape) sdf_drawing.DrawUniform {
        const stroke_width = path_utils.SKELETON_LINE_WIDTH * self.sdf_scale * shared.ui_scale;
        return sdf_drawing.DrawUniform{
            .solid = .{
                .dist_start = stroke_width * 0.5,
                .dist_end = -stroke_width * 0.5,
                .color = .{ 0.0, 0.0, 1.0, 1.0 },
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

        path_utils.prepareHalfStraightLines(points.items);

        return points.toOwnedSlice();
    }

    pub fn getPickUniform(self: Shape, effect: sdf_effect.Effect) PickUniform {
        return PickUniform{
            .dist_start = effect.dist_start * self.sdf_tex.scale,
            .dist_end = effect.dist_end * self.sdf_tex.scale,
        };
    }

    pub fn getDrawUniform(self: Shape, effect: sdf_effect.Effect) sdf_drawing.DrawUniform {
        return sdf_drawing.getDrawUniform(
            effect,
            self.sdf_tex.scale,
            self.props.opacity,
        );
    }

    pub fn getRelativePoints(self: *Shape, allocator: std.mem.Allocator) !?[]Point {
        if (!self.sdf_tex.is_outdated and !self.should_update_sdf) {
            @panic("getRelativePoints was called but the shape sdf was not marked as outdated!");
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

        for (points) |*point| {
            const scaled = scale.get(point);
            point.x = scaled.x;
            point.y = scaled.y;
        }

        return points;
    }

    pub fn getDrawBounds(self: Shape) [6]PointUV {
        // shape.sdf_size includes effects padding, safety padding and rounding error
        // to be able to compare them(obtain scale) together we have to calculate
        // world size -> bounds size + effects padding
        // sdf size -> shape.sdf_size - effects padding - rounding error

        // TODO: move this and same secito nfrom texts.Text to dedicated function
        const effects_padding_world = sdf_drawing.getSdfPadding(self.effects.items);
        const world_width = self.bounds[0].distance(self.bounds[1]) + 2 * effects_padding_world;

        // We assume all sdf texture keeps aspect ratio, just sdf_round_err breakes their aspect ratio

        const sdf_world_width = self.sdf_tex.size.w - (2 * consts.SDF_SAFE_PADDING + self.sdf_tex.round_err.x);
        const scale_world_vs_sdf = world_width / sdf_world_width; // NOTE: shoudln't we include osmehow here case if effects are too large
        const padding_world = effects_padding_world + consts.SDF_SAFE_PADDING * scale_world_vs_sdf;

        const scaled_sdf_round_err = Point{
            .x = self.sdf_tex.round_err.x * scale_world_vs_sdf,
            .y = self.sdf_tex.round_err.y * scale_world_vs_sdf,
        };

        return sdf_drawing.getDrawBoundsWorld(
            self.bounds,
            padding_world,
            self.getFilterMargin(),
            scaled_sdf_round_err,
        );
    }

    pub fn getPickBounds(self: Shape) [6]images.PickVertex {
        const bounds = self.getDrawBounds();
        var buffer: [6]images.PickVertex = undefined;
        for (bounds, 0..) |b, i| {
            buffer[i] = .{
                .point = b,
                .id = .{ self.id, 0, 0, 0 },
            };
        }
        return buffer;
    }

    pub fn getFilterMargin(self: Shape) Point {
        return if (self.props.blur) |blur| Point{
            .x = 3 * blur.x,
            .y = 3 * blur.y,
        } else consts.POINT_ZERO;
    }

    pub fn serialize(self: Shape, allocator: std.mem.Allocator) !Serialized {
        var paths_list = std.ArrayList([]const Point).init(allocator);
        for (self.paths.items) |path| {
            const serialized_path = path.serialize();
            try paths_list.append(serialized_path);
        }

        return Serialized{
            .id = self.id,
            .paths = try paths_list.toOwnedSlice(),
            .bounds = self.bounds,
            .props = self.props,
            .effects = try sdf_effect.serialize(self.effects, allocator),
            .sdf_texture_id = self.sdf_tex.id,
            .cache_texture_id = self.cache_texture_id,
        };
    }

    pub fn deinit(self: *Shape) void {
        for (self.paths.items) |*path| {
            path.deinit();
        }
        self.paths.deinit();
        sdf_effect.deinit(self.effects);
    }
};

pub const PickUniform = struct {
    dist_start: f32,
    dist_end: f32,
};

pub const Serialized = struct {
    id: u32,
    paths: []const []const Point,
    bounds: [4]PointUV,
    props: asset_props.Props,
    effects: []const sdf_effect.Serialized,
    sdf_texture_id: u32,
    cache_texture_id: ?u32,

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
            self.props.compare(other.props) and
            sdf_effect.compareSerialized(self.effects, other.effects) and
            utils.compareBounds(self.bounds, other.bounds);

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
