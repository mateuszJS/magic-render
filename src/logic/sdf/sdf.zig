const Point = @import("../types.zig").Point;
const fill = @import("fill.zig");

pub const Effect = struct {
    dist_start: f32,
    dist_end: f32,
    fill: fill.Fill,
};

pub const DrawUniform = union(enum) {
    solid: UniformSolid,
    linear: UniformLinearGradient,
    radial: UniformRadialGradient,
};

const UniformSolid = extern struct {
    dist_start: f32,
    dist_end: f32,
    padding: [2]u32 = .{ 0, 0 },
    color: @Vector(4, f32),
};

const UniformGradientStop = extern struct {
    color: [4]f32 = .{ 0.0, 0.0, 0.0, 0.0 },
    offset: f32 = 0.0,
    padding: [3]u32 = .{ 0, 0, 0 },
};

const UniformLinearGradient = extern struct {
    dist_start: f32,
    dist_end: f32,
    stops_count: u32,
    padding: u32 = 0.0,
    start: Point,
    end: Point,
    stops: [10]UniformGradientStop,
};

const UniformRadialGradient = extern struct {
    dist_start: f32,
    dist_end: f32,
    stops_count: u32,
    radius_ratio: f32,
    center: Point,
    destination: Point, // rx, ry for elliptical gradients
    stops: [10]UniformGradientStop,
};

pub fn getDrawUniform(sdf_effect: Effect, sdf_scale: f32, opacity: f32) DrawUniform {
    switch (sdf_effect.fill) {
        .solid => |color| {
            return DrawUniform{
                .solid = .{
                    .dist_start = sdf_effect.dist_start * sdf_scale,
                    .dist_end = sdf_effect.dist_end * sdf_scale,
                    .color = .{
                        color[0] * opacity,
                        color[1] * opacity,
                        color[2] * opacity,
                        color[3] * opacity,
                    },
                },
            };
        },
        .linear => |gradient| {
            var stops: [10]UniformGradientStop = undefined;
            for (gradient.stops.items, 0..) |stop, i| {
                stops[i] = UniformGradientStop{
                    .offset = stop.offset,
                    .color = .{
                        stop.color[0] * opacity,
                        stop.color[1] * opacity,
                        stop.color[2] * opacity,
                        stop.color[3] * opacity,
                    },
                };
            }
            return DrawUniform{
                .linear = .{
                    .dist_start = sdf_effect.dist_start * sdf_scale,
                    .dist_end = sdf_effect.dist_end * sdf_scale,
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
                    .color = .{
                        stop.color[0] * opacity,
                        stop.color[1] * opacity,
                        stop.color[2] * opacity,
                        stop.color[3] * opacity,
                    },
                };
            }

            return DrawUniform{
                .radial = .{
                    .dist_start = sdf_effect.dist_start * sdf_scale,
                    .dist_end = sdf_effect.dist_end * sdf_scale,
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
