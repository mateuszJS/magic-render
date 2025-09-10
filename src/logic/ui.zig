const std = @import("std");
const shapes = @import("shapes/shapes.zig");
const texture_size = @import("texture_size.zig");
const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;

var elements: std.AutoArrayHashMap(u32, shapes.Shape) = undefined;

pub fn init() void {
    elements = std.AutoArrayHashMap(u32, shapes.Shape).init(std.heap.page_allocator);
}

pub fn importUiElement(
    id: u32,
    paths: []const []const Point,
    sdf_texture_id: u32,
) !void {
    const props = shapes.SerializedProps{
        .sdf_effects = &.{},
        .filter = null,
        .opacity = 1.0,
    };
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

pub fn generateUiElementsSdf(compute_shape: *const fn ([]const Point, f32, f32, u32) void) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var iterator = elements.iterator();
    while (iterator.next()) |entry| {
        var shape = entry.value_ptr;
        const option_points = try shape.getNewSdfPoint(allocator);
        if (option_points) |points| {
            const bounds = shape.getBoundsWithPadding(1, false);
            shape.sdf_size = texture_size.get_sdf_size(bounds);
            compute_shape(
                points,
                @floor(shape.sdf_size.w),
                @floor(shape.sdf_size.h),
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
    draw_shape: *const fn ([]const PointUV, shapes.DrawUniform, u32) void,
) !void {
    for (dataset) |data| {
        if (elements.get(@intFromEnum(data.icon))) |shape| {
            const uniform = shapes.DrawUniform{
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
