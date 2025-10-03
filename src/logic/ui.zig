const std = @import("std");
const shapes = @import("shapes/shapes.zig");
const asset_props = @import("asset_props.zig");
const texture_size = @import("texture_size.zig");
const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const sdf = @import("sdf/sdf.zig");

var elements: std.AutoArrayHashMap(u32, shapes.Shape) = undefined;

pub fn init() void {
    elements = std.AutoArrayHashMap(u32, shapes.Shape).init(std.heap.page_allocator);
}

pub fn importUiElement(
    id: u32,
    paths: []const []const Point,
    sdf_texture_id: u32,
) !void {
    const props = asset_props.SerializedProps{};
    const shape = try shapes.Shape.new(
        0,
        paths,
        null,
        props,
        sdf_texture_id,
        0,
        std.heap.page_allocator,
    );
    try elements.put(id, shape);
}

pub fn generateUiElementsSdf(compute_shape: *const fn ([]const Point, u32, u32, u32) void) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var iterator = elements.iterator();
    while (iterator.next()) |entry| {
        var shape = entry.value_ptr;
        const option_points = try shape.getRelativePoints(allocator);
        if (option_points) |points| {
            const sdf_padding = sdf.getSdfPadding(shape.props.sdf_effects.items);
            const bounds = sdf.getBoundsWithPadding(
                shape.bounds,
                sdf_padding,
                1,
                null,
            );
            shape.sdf_size = texture_size.get_allowed_sdf_size(
                texture_size.get_allowed_size(
                    bounds[0].distance(bounds[1]),
                    bounds[0].distance(bounds[3]),
                ),
            );
            compute_shape(
                points,
                @intFromFloat(@floor(shape.sdf_size.w)),
                @intFromFloat(@floor(shape.sdf_size.h)),
                shape.sdf_texture_id,
            );
        }
    }
}

pub const IconType = enum(u32) { Rotate = 0 };

pub const DrawVertex = struct {
    position: Point,
    max_size: f32,
    icon: IconType,
    color: @Vector(4, f32),
};

pub fn draw(
    dataset: []DrawVertex,
    draw_shape: *const fn ([]const PointUV, sdf.DrawUniform, u32) void,
) !void {
    for (dataset) |data| {
        if (elements.get(@intFromEnum(data.icon))) |shape| {
            const uniform = sdf.DrawUniform{
                .solid = .{
                    .dist_start = std.math.inf(f32),
                    .dist_end = 0,
                    .color = data.color,
                },
            };

            const p = data.position;
            const max_sdf_size = @max(shape.sdf_size.w, shape.sdf_size.h);
            const scale = data.max_size / max_sdf_size;

            const hw = scale * shape.sdf_size.w * 0.5; // half width
            const hh = scale * shape.sdf_size.h * 0.5; // half height

            const vertex = [6]PointUV{
                .{ .x = p.x - hw, .y = p.y - hh, .u = 0.0, .v = 0.0 },
                .{ .x = p.x - hw, .y = p.y + hh, .u = 0.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y + hh, .u = 1.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y + hh, .u = 1.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y - hh, .u = 1.0, .v = 0.0 },
                .{ .x = p.x - hw, .y = p.y - hh, .u = 0.0, .v = 0.0 },
            };

            draw_shape(
                &vertex,
                uniform,
                shape.sdf_texture_id,
            );
        }
    }
}

pub fn deinit() void {
    var it = elements.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit();
    }
    elements.clearAndFree();
}
