const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const texture_size = @import("../texture_size.zig");
const fill = @import("fill.zig");
const std = @import("std");
const shared = @import("../shared.zig");
const consts = @import("../consts.zig");
const Effect = @import("effect.zig").Effect;
const SKELETON_LINE_WIDTH = @import("../shapes/path_utils.zig").SKELETON_LINE_WIDTH;

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

pub fn getSdfPadding(effects: []Effect, bounds: [4]PointUV) f32 {
    var padding: f32 = SKELETON_LINE_WIDTH / 2; // at least 1, without fwidth fix
    // because of skeleton render, we cannot od less than zero

    for (effects) |effect| {
        if (effect.dist_end > 9999999) {
            @panic("SDF effect dist_end should NOT be a large positive number!");
        }
        padding = @max(padding, -effect.dist_end);
    }

    // we do smoothing in shaders with fwidth(), so it's 1px to make sure we wont cut it out
    padding += @max(3.0, 1.0 * getRatioPxPerSdfTexel(bounds)); // 1px guard for fwidth() smoothing

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

    const edge_x = Point{
        .x = bounds[1].x - bounds[0].x,
        .y = bounds[1].y - bounds[0].y,
    };
    const edge_y = Point{
        .x = bounds[3].x - bounds[0].x,
        .y = bounds[3].y - bounds[0].y,
    };

    const edge_x_len = edge_x.length();
    const edge_y_len = edge_y.length();

    const axis_x = Point{ .x = edge_x.x / edge_x_len, .y = edge_x.y / edge_x_len };
    const axis_y = Point{ .x = edge_y.x / edge_y_len, .y = edge_y.y / edge_y_len };

    const offset_x = Point{
        .x = axis_x.x * padding.x,
        .y = axis_x.y * padding.x,
    };

    const offset_y = Point{
        .x = axis_y.x * padding.y,
        .y = axis_y.y * padding.y,
    };

    var buffer: [4]PointUV = bounds;

    buffer[0].x = (bounds[0].x - offset_x.x - offset_y.x) * scale;
    buffer[0].y = (bounds[0].y - offset_x.y - offset_y.y) * scale;

    buffer[1].x = (bounds[1].x + offset_x.x - offset_y.x) * scale;
    buffer[1].y = (bounds[1].y + offset_x.y - offset_y.y) * scale;

    buffer[2].x = (bounds[2].x + offset_x.x + offset_y.x) * scale;
    buffer[2].y = (bounds[2].y + offset_x.y + offset_y.y) * scale;

    buffer[3].x = (bounds[3].x - offset_x.x + offset_y.x) * scale;
    buffer[3].y = (bounds[3].y - offset_x.y + offset_y.y) * scale;

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

// Progressive ratio: 1 texel per px below 50px viewport size, doubling thresholds above.
// Formula: max(1, ceil(log2(viewport_size / 50)) + 1)
// Results: <=50->1, (50,100]->2, (100,200]->3, (200,400]->4, ...
// fn getRatioPxPerSdfTexel(bounds: [4]PointUV) f32 {
//     const max_dim = @max(bounds[0].distance(bounds[1]), bounds[0].distance(bounds[3]));
//     const viewport_size = max_dim * shared.render_scale;
//     const normalized = viewport_size / 50.0;
//     if (normalized <= 1.0) return 1.0;
//     return 4 * @ceil(std.math.log2(normalized)) + 1.0;
// }
// fn getRatioPxPerSdfTexel(bounds: [4]PointUV, optimise: bool) f32 {
fn getRatioPxPerSdfTexel(bounds: [4]PointUV) f32 {
    const max_dim = @max(bounds[0].distance(bounds[1]), bounds[0].distance(bounds[3]));
    const viewport_size = max_dim / shared.render_scale;
    if (viewport_size <= 50.0) return 1.0;
    // std.debug.print("shared.pixel_density: {d}\n", .{shared.pixel_density});
    if (shared.pixel_density + consts.EPSILON >= 3.0) {
        // tested on retina screen, 3 device px per 1 CSS pixel
        // Retina loss - abouve thta not much improvements
        // 10 -> 300
        // 8 -> 235
        // 6 -> 175
        // 4 -> 75
        // 2 -> 33
        // std.debug.print("333333333\n", .{});
        return @max(1, 0.65 * @sqrt(viewport_size) - 1.9);
    } else if (shared.pixel_density + consts.EPSILON >= 2.0) {
        // tested on retina screen, 2 device px per 1 CSS pixel
        // https://quickchart.io/chart?c=%7B%22type%22%3A%22scatter%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%220.026x%2B0.9%22%2C%22data%22%3A%5B%7B%22x%22%3A0%2C%22y%22%3A0.9%7D%2C%7B%22x%22%3A50%2C%22y%22%3A2.2%7D%2C%7B%22x%22%3A100%2C%22y%22%3A3.5%7D%2C%7B%22x%22%3A150%2C%22y%22%3A4.8%7D%2C%7B%22x%22%3A200%2C%22y%22%3A6.1%7D%2C%7B%22x%22%3A250%2C%22y%22%3A7.4%7D%2C%7B%22x%22%3A300%2C%22y%22%3A8.7%7D%2C%7B%22x%22%3A350%2C%22y%22%3A10.0%7D%5D%2C%22showLine%22%3Atrue%2C%22pointRadius%22%3A0%2C%22borderColor%22%3A%22blue%22%7D%2C%7B%22label%22%3A%22target+points%22%2C%22data%22%3A%5B%7B%22x%22%3A40%2C%22y%22%3A2%7D%2C%7B%22x%22%3A120%2C%22y%22%3A4%7D%2C%7B%22x%22%3A210%2C%22y%22%3A6%7D%2C%7B%22x%22%3A260%2C%22y%22%3A8%7D%2C%7B%22x%22%3A350%2C%22y%22%3A10%7D%5D%2C%22pointRadius%22%3A6%2C%22backgroundColor%22%3A%22red%22%7D%5D%7D%7D
        // Retina loss - abouve thta not much improvements
        // 10 -> 350
        // 8 -> 260
        // 6 -> 210
        // 4 -> 120
        // 2 -> 40
        // std.debug.print("222222222\n", .{});
        return @max(1, 0.026 * viewport_size + 0.9);
    } else {
        // tested on non-retina screen, 1 device px per 1 CSS pixel
        // https://quickchart.io/chart?c=%7B%22type%22%3A%22scatter%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%220.53%E2%88%9Ax-3%22%2C%22data%22%3A%5B%7B%22x%22%3A0%2C%22y%22%3A-3%7D%2C%7B%22x%22%3A50%2C%22y%22%3A0.75%7D%2C%7B%22x%22%3A100%2C%22y%22%3A2.3%7D%2C%7B%22x%22%3A150%2C%22y%22%3A3.49%7D%2C%7B%22x%22%3A200%2C%22y%22%3A4.49%7D%2C%7B%22x%22%3A250%2C%22y%22%3A5.38%7D%2C%7B%22x%22%3A300%2C%22y%22%3A6.18%7D%2C%7B%22x%22%3A350%2C%22y%22%3A6.92%7D%2C%7B%22x%22%3A400%2C%22y%22%3A7.6%7D%2C%7B%22x%22%3A450%2C%22y%22%3A8.24%7D%2C%7B%22x%22%3A500%2C%22y%22%3A8.85%7D%2C%7B%22x%22%3A550%2C%22y%22%3A9.43%7D%2C%7B%22x%22%3A600%2C%22y%22%3A9.98%7D%2C%7B%22x%22%3A700%2C%22y%22%3A11.02%7D%5D%2C%22showLine%22%3Atrue%2C%22pointRadius%22%3A0%2C%22borderColor%22%3A%22blue%22%7D%2C%7B%22label%22%3A%22target+points%22%2C%22data%22%3A%5B%7B%22x%22%3A86%2C%22y%22%3A2%7D%2C%7B%22x%22%3A180%2C%22y%22%3A4%7D%2C%7B%22x%22%3A280%2C%22y%22%3A6%7D%2C%7B%22x%22%3A420%2C%22y%22%3A8%7D%2C%7B%22x%22%3A600%2C%22y%22%3A10%7D%5D%2C%22pointRadius%22%3A6%2C%22backgroundColor%22%3A%22red%22%7D%5D%7D%7D
        // loss - good enough, above that not much improvements(used as data for graph), really good:
        // 10 -> 400, 600, 850
        // 8 -> 320, 420, 500
        // 6 -> 230, 280, 450
        // 4 -> 140, 180, 200
        // 2 -> 73,  86, 100
        // std.debug.print("111111111\n", .{});
        return @max(1, 0.53 * @sqrt(viewport_size) - 3);
    }
}

pub fn getSdfTextureDims(
    bounds: [4]PointUV,
    sdf_padding: f32,
    optimise: bool,
) struct {
    size: texture_size.TextureSize,
    scale: f32,
} {
    if (optimise) {
        std.debug.print("letter size: {d}\n", .{
            @max(bounds[0].distance(bounds[1]), bounds[0].distance(bounds[3])) / shared.render_scale,
        });
    }

    // const ratio: f32 = getRatioPxPerSdfTexel(bounds, optimise); // getRatioPxPerSdfTexel(bounds);
    const ratio: f32 = if (optimise) getRatioPxPerSdfTexel(bounds) else 1; // getRatioPxPerSdfTexel(bounds);
    const bounds_with_padding = getBoundsWithPadding(
        bounds,
        sdf_padding,
        1 / (shared.render_scale * ratio),
        null,
    );

    const desired_size = texture_size.get_allowed_size(
        bounds_with_padding[0].distance(bounds_with_padding[1]),
        bounds_with_padding[0].distance(bounds_with_padding[3]),
    );

    const sdf_size = texture_size.get_allowed_sdf_size(desired_size);
    const sdf_safe_size = texture_size.TextureSize{
        .w = @max(sdf_size.w, consts.MIN_TEXTURE_SIZE),
        .h = @max(sdf_size.h, consts.MIN_TEXTURE_SIZE),
    };

    const init_width = bounds_with_padding[0].distance(bounds_with_padding[1]) * (shared.render_scale * ratio);
    // * shared.render_scale to revert to logical scale (without impact of camera/zoom)
    const sdf_scale = sdf_safe_size.w / init_width;

    return .{
        .size = sdf_safe_size,
        .scale = sdf_scale,
    };
}
