const std = @import("std");
const shapes = @import("shapes/shapes.zig");
const asset_props = @import("asset_props.zig");
const texture_size = @import("texture_size.zig");
const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const sdf_drawing = @import("sdf/drawing.zig");
const consts = @import("consts.zig");
const computeShape = @import("compute_shape.zig").computeShape;
const webgpu_glue = @import("webgpu_glue.zig");

var elements: std.AutoArrayHashMap(u32, shapes.Shape) = undefined;

pub fn init() void {
    elements = std.AutoArrayHashMap(u32, shapes.Shape).init(std.heap.page_allocator);
}

pub fn importUiElement(
    id: u32,
    paths: []const []const Point,
    sdf_texture_id: u32,
) !void {
    const props = asset_props.Props{};
    const shape = try shapes.Shape.new(
        0,
        paths,
        consts.DEFAULT_BOUNDS,
        props,
        &.{},
        sdf_texture_id,
        0,
        std.heap.page_allocator,
    );

    try elements.put(id, shape);
}

pub fn generateUiElementsSdf() !void {
    var iterator = elements.iterator();
    while (iterator.next()) |entry| {
        var shape = entry.value_ptr;
        const option_points = try shape.getRelativePoints(std.heap.page_allocator);
        if (option_points) |points| {
            const sdf_padding = sdf_drawing.getSdfPadding(shape.effects.items);

            shape.sdf_tex.deinit();
            shape.sdf_tex = try computeShape(
                shape.sdf_tex.id,
                shape.bounds,
                sdf_padding,
                points,
                1,
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

pub fn draw(dataset: []DrawVertex) !void {
    for (dataset) |data| {
        if (elements.get(@intFromEnum(data.icon))) |shape| {
            const uniform = sdf_drawing.DrawUniform{
                .solid = .{
                    .dist_start = consts.INFINITE_DISTANCE,
                    .dist_end = 0,
                    .color = data.color,
                },
            };

            const p = data.position;
            const max_sdf_size = @max(shape.sdf_tex.size.w, shape.sdf_tex.size.h);
            const scale = data.max_size / max_sdf_size;

            const hw = scale * shape.sdf_tex.size.w * 0.5; // half width
            const hh = scale * shape.sdf_tex.size.h * 0.5; // half height

            const vertex = [6]PointUV{
                .{ .x = p.x - hw, .y = p.y - hh, .u = 0.0, .v = 0.0 },
                .{ .x = p.x - hw, .y = p.y + hh, .u = 0.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y + hh, .u = 1.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y + hh, .u = 1.0, .v = 1.0 },
                .{ .x = p.x + hw, .y = p.y - hh, .u = 1.0, .v = 0.0 },
                .{ .x = p.x - hw, .y = p.y - hh, .u = 0.0, .v = 0.0 },
            };

            webgpu_glue.draw_shape(
                &vertex,
                uniform,
                shape.sdf_tex.id,
                shape.sdf_tex.points,
                shape.sdf_tex.uniform_t,
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
