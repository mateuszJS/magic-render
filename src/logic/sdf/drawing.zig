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

pub fn getSdfPadding(effects: []Effect, loss: f32) f32 {
    var padding: f32 = SKELETON_LINE_WIDTH / 2; // at least 1, without fwidth fix
    // because of skeleton render, we cannot od less than zero

    for (effects) |effect| {
        if (effect.dist_end > 9999999) {
            @panic("SDF effect dist_end should NOT be a large positive number!");
        }
        padding = @max(padding, -effect.dist_end);
    }

    _ = loss;
    // padding += 1.0; // idk why 4, lower valeus still cuase bleed,
    // maybe it's indirectional effect of because of multisampling of 4?
    // 4 texels to stop bleeding texture

    return padding;
}

pub fn getBoundsWithPadding(bounds: [4]PointUV, sdf_padding: f32, scale: f32, filter_margin: ?Point) [4]PointUV {
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

pub fn getBoundsWithPaddingEnhanced(
    bounds: [4]PointUV,
    sdf_padding: f32,
    scale: f32,
    filter_margin: ?Point,
    tex_round_err: Point,
) [4]PointUV {
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
    // I assume this -1 is related to texutre coordinate system, it just works
    buffer[0].y = (bounds[0].y - offset_x.y - offset_y.y) * scale + tex_round_err.y * axis_y.y * -1;

    buffer[1].x = (bounds[1].x + offset_x.x - offset_y.x) * scale + tex_round_err.x * axis_x.x;
    buffer[1].y = (bounds[1].y + offset_x.y - offset_y.y) * scale + tex_round_err.y * axis_y.y * -1;

    buffer[2].x = (bounds[2].x + offset_x.x + offset_y.x) * scale + tex_round_err.x * axis_x.x;
    buffer[2].y = (bounds[2].y + offset_x.y + offset_y.y) * scale;

    buffer[3].x = (bounds[3].x - offset_x.x + offset_y.x) * scale;
    buffer[3].y = (bounds[3].y - offset_x.y + offset_y.y) * scale;

    return buffer;
}

pub fn getDrawBoundsWorld(
    bounds: [4]PointUV,
    padding: f32,
    filter_margin: ?Point,
    tex_round_err: Point,
) [6]PointUV {
    const bounds_with_padding = getBoundsWithPaddingEnhanced(
        bounds,
        padding,
        1,
        filter_margin,
        tex_round_err,
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

// returns how much combine SDF ratio should be vs normal SDF
// Combined SDFs need denser sampling
pub fn getCombineSdfRatio() f32 {
    if (shared.pixel_density + consts.EPSILON >= 3.0) {
        return 0.1;
    } else if (shared.pixel_density + consts.EPSILON >= 2.0) {
        return 0.02;
    } else {
        return 1; // TEST it on non-retina
    }
}

pub fn getRatioPxPerSdfTexel(bounds: [4]PointUV) f32 {
    const max_dim = @max(bounds[0].distance(bounds[1]), bounds[0].distance(bounds[3]));
    const viewport_size = max_dim / shared.render_scale;

    if (shared.pixel_density + consts.EPSILON >= 3.0) {
        // tested on retina screen, 3 device px per 1 CSS pixel
        // https://quickchart.io/chart?c=%7B%22type%22%3A%22scatter%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%220.65sqrt(x)-1.9%22%2C%22data%22%3A%5B%7B%22x%22%3A0%2C%22y%22%3A-1.9%7D%2C%7B%22x%22%3A50%2C%22y%22%3A2.7%7D%2C%7B%22x%22%3A100%2C%22y%22%3A4.6%7D%2C%7B%22x%22%3A150%2C%22y%22%3A6.1%7D%2C%7B%22x%22%3A200%2C%22y%22%3A7.3%7D%2C%7B%22x%22%3A250%2C%22y%22%3A8.4%7D%2C%7B%22x%22%3A300%2C%22y%22%3A9.4%7D%2C%7B%22x%22%3A350%2C%22y%22%3A10.3%7D%5D%2C%22showLine%22%3Atrue%2C%22pointRadius%22%3A0%2C%22borderColor%22%3A%22blue%22%7D%2C%7B%22label%22%3A%22target+points%22%2C%22data%22%3A%5B%7B%22x%22%3A33%2C%22y%22%3A2%7D%2C%7B%22x%22%3A75%2C%22y%22%3A4%7D%2C%7B%22x%22%3A175%2C%22y%22%3A6%7D%2C%7B%22x%22%3A235%2C%22y%22%3A8%7D%2C%7B%22x%22%3A300%2C%22y%22%3A10%7D%5D%2C%22pointRadius%22%3A6%2C%22backgroundColor%22%3A%22red%22%7D%5D%7D%7D
        // Retina loss - abouve thta not much improvements
        // 300 -> 10
        // 235 -> 8
        // 175 -> 6
        //  75 -> 4
        //  33 -> 2
        return @max(1, 0.65 * @sqrt(viewport_size) - 1.9);
    } else if (shared.pixel_density + consts.EPSILON >= 2.0) {
        // tested on retina screen, 2 device px per 1 CSS pixel
        // https://quickchart.io/chart?c=%7B%22type%22%3A%22scatter%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%220.026x%2B0.9%22%2C%22data%22%3A%5B%7B%22x%22%3A0%2C%22y%22%3A0.9%7D%2C%7B%22x%22%3A50%2C%22y%22%3A2.2%7D%2C%7B%22x%22%3A100%2C%22y%22%3A3.5%7D%2C%7B%22x%22%3A150%2C%22y%22%3A4.8%7D%2C%7B%22x%22%3A200%2C%22y%22%3A6.1%7D%2C%7B%22x%22%3A250%2C%22y%22%3A7.4%7D%2C%7B%22x%22%3A300%2C%22y%22%3A8.7%7D%2C%7B%22x%22%3A350%2C%22y%22%3A10.0%7D%5D%2C%22showLine%22%3Atrue%2C%22pointRadius%22%3A0%2C%22borderColor%22%3A%22blue%22%7D%2C%7B%22label%22%3A%22target+points%22%2C%22data%22%3A%5B%7B%22x%22%3A40%2C%22y%22%3A2%7D%2C%7B%22x%22%3A120%2C%22y%22%3A4%7D%2C%7B%22x%22%3A210%2C%22y%22%3A6%7D%2C%7B%22x%22%3A260%2C%22y%22%3A8%7D%2C%7B%22x%22%3A350%2C%22y%22%3A10%7D%5D%2C%22pointRadius%22%3A6%2C%22backgroundColor%22%3A%22red%22%7D%5D%7D%7D
        // Retina loss - abouve thta not much improvements
        // 350 -> 10
        // 260 -> 8
        // 210 -> 6
        // 120 -> 4
        //  40 -> 2
        return @max(1, 0.026 * viewport_size + 0.9);
    } else {
        // std.debug.print("viewport_size {d}\n", .{viewport_size});
        // tested on non-retina screen, 1 device px per 1 CSS pixel
        // https://quickchart.io/chart?c=%7B%22type%22%3A%22scatter%22%2C%22data%22%3A%7B%22datasets%22%3A%5B%7B%22label%22%3A%220.53%E2%88%9Ax-3%22%2C%22data%22%3A%5B%7B%22x%22%3A0%2C%22y%22%3A-3%7D%2C%7B%22x%22%3A50%2C%22y%22%3A0.75%7D%2C%7B%22x%22%3A100%2C%22y%22%3A2.3%7D%2C%7B%22x%22%3A150%2C%22y%22%3A3.49%7D%2C%7B%22x%22%3A200%2C%22y%22%3A4.49%7D%2C%7B%22x%22%3A250%2C%22y%22%3A5.38%7D%2C%7B%22x%22%3A300%2C%22y%22%3A6.18%7D%2C%7B%22x%22%3A350%2C%22y%22%3A6.92%7D%2C%7B%22x%22%3A400%2C%22y%22%3A7.6%7D%2C%7B%22x%22%3A450%2C%22y%22%3A8.24%7D%2C%7B%22x%22%3A500%2C%22y%22%3A8.85%7D%2C%7B%22x%22%3A550%2C%22y%22%3A9.43%7D%2C%7B%22x%22%3A600%2C%22y%22%3A9.98%7D%2C%7B%22x%22%3A700%2C%22y%22%3A11.02%7D%5D%2C%22showLine%22%3Atrue%2C%22pointRadius%22%3A0%2C%22borderColor%22%3A%22blue%22%7D%2C%7B%22label%22%3A%22target+points%22%2C%22data%22%3A%5B%7B%22x%22%3A86%2C%22y%22%3A2%7D%2C%7B%22x%22%3A180%2C%22y%22%3A4%7D%2C%7B%22x%22%3A280%2C%22y%22%3A6%7D%2C%7B%22x%22%3A420%2C%22y%22%3A8%7D%2C%7B%22x%22%3A600%2C%22y%22%3A10%7D%5D%2C%22pointRadius%22%3A6%2C%22backgroundColor%22%3A%22red%22%7D%5D%7D%7D
        // loss - good enough, above that not much improvements(used as data for graph), really good:
        // 600 -> 10
        // 420 -> 8
        // 280 -> 6
        // 180 -> 4
        //  86 -> 2

        return 20;
        // return @max(1, 0.53 * @sqrt(viewport_size) - 3);
    }
}

pub fn getSdfTextureDims(
    bounds: [4]PointUV,
    sdf_padding: f32,
    loss_factor: f32,
    additional_scale: f32,
    // used to generate 20% bigger textures, so we won't need to regenerate
    // again texture while user is zooming in slowly (so would trigger
    // new SDF each frame)
) struct {
    size: texture_size.TextureSize,
    scale: f32,
    sdf_rounding_err: Point,
} {
    // var loss_ratio: f32 = getRatioPxPerSdfTexel(bounds);
    // if (combine_sdf) {
    //     loss_ratio = @max(1, loss_ratio * getCombineSdfRatio());
    // }

    // loss_ratio = 1;
    // _ = additional_scale;
    const scale = additional_scale / (shared.render_scale * loss_factor);

    // The 1px fwidth guard in sdf_padding needs to remain 1 SDF texel after
    // the scale reduction. 1 texel = 1/scale world units, so compensate the gap:
    // const fwidth_compensation = (1.0 / scale) - 1.0;
    const bounds_with_padding = getBoundsWithPadding(
        bounds,
        sdf_padding, // + fwidth_compensation,
        scale,
        null,
    );

    // Here, we have to check if its allowed size BUT
    // still handle 1 texel extra padding from each side!

    const desired_size = texture_size.get_allowed_size(
        bounds_with_padding[0].distance(bounds_with_padding[1]),
        bounds_with_padding[0].distance(bounds_with_padding[3]),
    );

    const sdf_size = texture_size.get_allowed_sdf_size(desired_size);

    const world_width = bounds_with_padding[0].distance(bounds_with_padding[1]) / scale;
    // * shared.render_scale to revert to logical scale (without impact of camera/zoom)

    const sdf_scale = sdf_size.w / world_width;
    std.debug.print("sdf_scale {d}\n", .{sdf_scale});

    const sdf_safe_size = texture_size.TextureSize{
        .w = @ceil(sdf_size.w) + 2, // 1 texel left and right bot safety
        .h = @ceil(sdf_size.h) + 2, // 1 texel top and bottom for safety
    };

    return .{
        .size = sdf_safe_size, // rounded ceil size
        .scale = sdf_scale, // scale taken before rounding
        .sdf_rounding_err = Point{
            .x = @ceil(sdf_size.w) - sdf_size.w,
            .y = @ceil(sdf_size.h) - sdf_size.h,
        },
    };
}
