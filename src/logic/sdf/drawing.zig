const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const texture_size = @import("../texture_size.zig");
const fill = @import("fill.zig");
const std = @import("std");
const shared = @import("../shared.zig");
const consts = @import("../consts.zig");
const Effect = @import("effect.zig").Effect;

pub const DrawUniform = union(enum) {
    solid: UniformSolid,
    linear: UniformLinearGradient,
    radial: UniformRadialGradient,
    program: UniformProgram,
};

const UniformSolid = extern struct {
    dist_start: f32,
    dist_end: f32,
    padding: [2]u32 = .{ 0, 0 },
    color: @Vector(4, f32),
};

const UniformProgram = extern struct {
    program_id: u32,
    dist_start: f32,
    dist_end: f32,
    sdf_scale: f32,
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
    start: Point,
    end: Point, // rx, ry for elliptical gradients
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
                    .start = gradient.start,
                    .end = gradient.end,
                    .stops = stops,
                    .radius_ratio = gradient.radius_ratio,
                },
            };
        },
        .program_id => |id| {
            return DrawUniform{
                .program = .{
                    .program_id = id,
                    .dist_start = sdf_effect.dist_start * sdf_scale,
                    .dist_end = sdf_effect.dist_end * sdf_scale,
                    .sdf_scale = sdf_scale,
                },
            };
        },
    }
}

pub fn getSdfPadding(effects: []Effect) f32 {
    var padding: f32 = 0.0;
    // because of skeleton render, we cannot od less than zero

    for (effects) |effect| {
        if (effect.dist_end > 9999999) {
            std.debug.print("SDF effect dist_end should NOT be a large positive number!\n effect: {any}\n", .{effect});
            @panic("SDF effect dist_end should NOT be a large positive number!");
        }
        padding = @max(padding, -effect.dist_end);
    }

    // we do smoothing in shaders with fwidth(), so it's 1px to make sure we wont cut it out
    padding += 1.0;

    return padding;
}

pub fn getBoundsWithPadding(bounds: [4]PointUV, sdf_padding: f32, scale: f32, filter_margin: ?Point) [4]PointUV {
    // const sdf_padding = sdf.getSdfPadding(self.effects.items);
    var padding = Point{
        .x = sdf_padding,
        .y = sdf_padding,
    };

    if (filter_margin) |margin| {
        padding.x += margin.x;
        padding.y += margin.y;
    }

    var buffer: [4]PointUV = undefined;
    const bounds_len: usize = 4;
    for (bounds, 0..) |b, i| {
        const b_next = bounds[(i + 1) % bounds_len];
        const b_prev = bounds[@min((i -% 1), (bounds_len - 1)) % bounds_len];

        const angle_next = b.angleTo(b_next);
        const angle_prev = b.angleTo(b_prev);

        buffer[i] = b;
        buffer[i].x -= @cos(angle_next) * padding.x + @cos(angle_prev) * padding.x;
        buffer[i].y -= @sin(angle_next) * padding.y + @sin(angle_prev) * padding.y;
        buffer[i].x *= scale;
        buffer[i].y *= scale;
    }

    return buffer;
}

pub fn getDrawBounds(bounds: [4]PointUV, sdf_padding: f32, filter_margin: ?Point) [6]PointUV {
    const bounds_with_padding = getBoundsWithPadding(
        bounds,
        sdf_padding,
        1,
        filter_margin,
    );
    return [_]PointUV{
        // first triangle
        bounds_with_padding[0],
        bounds_with_padding[1],
        bounds_with_padding[2],
        // second triangle
        bounds_with_padding[2],
        bounds_with_padding[3],
        bounds_with_padding[0],
    };
}

pub fn getSdfTextureDims(bounds: [4]PointUV, sdf_padding: f32) struct {
    size: texture_size.TextureSize,
    scale: f32,
    // rounding_error: texture_size.TextureSize,
} {
    const bounds_with_padding = getBoundsWithPadding(
        bounds,
        sdf_padding,
        1 / shared.render_scale,
        null,
    );

    const desired_size = texture_size.get_allowed_size(
        bounds_with_padding[0].distance(bounds_with_padding[1]),
        bounds_with_padding[0].distance(bounds_with_padding[3]),
    );

    // TODO: recreate and solve this issue:
    // ceil because without it, while casting f32 to u32 it rounds down
    // and often the end of the texture cuts out large part of the padding and in the result shapes touched the edge
    // we cannot round above because it jumps between values, and we cannot do it below becuase it might be
    // bigger than max sdf size. We might just +1?

    const sdf_size = texture_size.get_allowed_sdf_size(desired_size);
    const sdf_safe_size = texture_size.TextureSize{
        .w = @max(sdf_size.w, consts.MIN_TEXTURE_SIZE),
        .h = @max(sdf_size.h, consts.MIN_TEXTURE_SIZE),
    };

    const init_width = bounds_with_padding[0].distance(bounds_with_padding[1]) * shared.render_scale;
    // * shared.render_scale to revert to logical scale (without impact of camera/zoom)
    const sdf_scale = sdf_safe_size.w / init_width;

    return .{
        .size = sdf_safe_size,
        .scale = sdf_scale,
        // .rounding_error = .{
        //     .w = sdf_safe_size.w - sdf_size.w,
        //     .h = sdf_safe_size.h - sdf_size.h,
        // },
    };
}
