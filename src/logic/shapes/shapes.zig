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
pub var cacheShape: *const fn (?u32, bounding_box.BoundingBox, DrawVertexOutput, f32, f32) u32 = undefined;
pub var maxTextureSize: f32 = 0.0;

pub const ShapeProps = struct {
    // f32 instead of u8 because Uniforms in wgsl doesn't support u8 anyway
    fill_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default fill color (red)
    stroke_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 }, // Default stroke color (green)
    stroke_width: f32 = 0.0, // Default stroke width
};

pub const TextureCache = struct {
    id: u32, // we ave to obtain it from JS, so it's null initially
    points: [4]PointUV,
    width: f32,
    height: f32,
    valid: bool = false,
};

pub const Shape = struct {
    id: u32,
    paths: std.ArrayList(Path),
    props: ShapeProps,
    cache: ?TextureCache = null,

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
    pub fn newFromPoints(id: u32, input_paths: []const []const Point, props: ShapeProps, cache: ?TextureCache, allocator: std.mem.Allocator) !Shape {
        var paths_list = std.ArrayList(Path).init(allocator);

        for (input_paths) |input_path| {
            const path = try Path.newFromPoints(input_path, allocator);
            try paths_list.append(path);
        }

        const shape = Shape{
            .id = id,
            .paths = paths_list,
            .props = props,
            .cache = cache,
        };

        return shape;
    }

    pub fn addPointStart(self: *Shape, allocator: std.mem.Allocator, point: Point, option_active_path_index: ?usize) !usize {
        if (option_active_path_index) |active_path_index| {
            var active_path = &self.paths.items[active_path_index];
            try active_path.addPoint(point);
            if (self.cache) |*cache| {
                cache.valid = false;
            }
            return active_path_index;
        } else {
            const new_path = try Path.new(point, allocator);
            try self.paths.append(new_path);
            return self.paths.items.len - 1;
        }
    }

    // receives boolean indicating if texture size was updated or not
    pub fn updateTextureSize(cache: *TextureCache) bool {
        const width = cache.points[0].distance(cache.points[1]);
        const height = cache.points[0].distance(cache.points[3]);
        const new_width = @min(Utils.getNextPowerOfTwo(@max(cache.width, width / shared.render_scale)), maxTextureSize);
        const new_height = @min(Utils.getNextPowerOfTwo(@max(cache.height, height / shared.render_scale)), maxTextureSize);

        if (cache.width > new_width - EPSILON and cache.height > new_height - EPSILON) {
            return false;
        }

        cache.width = new_width;
        cache.height = new_height;
        return true;
    }

    pub fn drawTextureCache(self: *Shape, allocator: std.mem.Allocator, force: bool) !void {
        var cache: TextureCache = undefined;
        var texture_id: ?u32 = null;

        // try to avoid undefined
        if (self.cache) |_cache| {
            if (_cache.valid and !force) return; // texture is up to date
            cache = _cache;
            texture_id = _cache.id;
        } else {
            cache = TextureCache{
                .id = undefined,
                .points = undefined,
                .width = 0.0,
                .height = 0.0,
            };
        }

        const option_vertex_output = try self.getDrawVertexData(
            allocator,
            null,
            null,
        );

        if (option_vertex_output) |vertex_output| {
            const left_bottom = vertex_output.bounding_box[0];
            const right_top = vertex_output.bounding_box[2];
            cache.points = [4]PointUV{
                .{ .x = left_bottom.x, .y = right_top.y, .u = 0.0, .v = 1.0 },
                .{ .x = right_top.x, .y = right_top.y, .u = 1.0, .v = 1.0 },
                .{ .x = right_top.x, .y = left_bottom.y, .u = 1.0, .v = 0.0 },
                .{ .x = left_bottom.x, .y = left_bottom.y, .u = 0.0, .v = 0.0 },
            };

            if (cache.width < EPSILON) {
                std.debug.print("Init cache texture size\n", .{});
                // we need to calculate bounding box first(we did this above) to set initial size
                _ = Shape.updateTextureSize(&cache);
            }

            const cache_bounding_box = bounding_box.BoundingBox{
                .min_x = left_bottom.x,
                .min_y = left_bottom.y,
                .max_x = right_top.x,
                .max_y = right_top.y,
            };

            cache.id = cacheShape(
                texture_id,
                cache_bounding_box,
                vertex_output,
                cache.width,
                cache.height,
            );

            cache.valid = false;
            self.cache = cache;
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

    pub fn getDrawVertexData(self: Shape, allocator: std.mem.Allocator, active_path_index: ?usize, option_preview_point: ?Point) !?DrawVertexOutput {
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

    pub fn getCacheTextureDrawVertexData(cache: TextureCache) images.DrawVertex {
        return images.DrawVertex{
            // first triangle
            cache.points[0],
            cache.points[1],
            cache.points[2],
            // second triangle
            cache.points[2],
            cache.points[3],
            cache.points[0],
        };
    }

    pub fn getCacheTexturePickVertexData(self: Shape, cache: TextureCache) [6]images.PickVertex {
        return [_]images.PickVertex{
            // first triangle
            .{ .id = self.id, .point = cache.points[0] },
            .{ .id = self.id, .point = cache.points[1] },
            .{ .id = self.id, .point = cache.points[2] },
            // second triangle
            .{ .id = self.id, .point = cache.points[2] },
            .{ .id = self.id, .point = cache.points[3] },
            .{ .id = self.id, .point = cache.points[0] },
        };
    }

    pub fn updateLastHandle(self: *Shape, active_path_index: usize, preview_point: Point) void {
        const active_path = &self.paths.items[active_path_index];
        active_path.updateLastHandle(preview_point);
        if (self.cache) |*cache| {
            cache.valid = false;
        }
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
