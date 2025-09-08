const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const shared = @import("shared.zig");
const std = @import("std");

pub const TextureSize = struct {
    w: f32,
    h: f32,
};

pub fn get_sdf_size(bounds: [4]PointUV) TextureSize {
    var size = get_size(bounds);
    const sdf_texture_size = size.w * size.h * 16;

    if (sdf_texture_size > shared.max_buffer_size) {
        const max_pixels = shared.max_buffer_size / 16.0;
        const ratio = max_pixels / (size.w * size.h);
        size.w *= ratio;
        size.h *= ratio;
    }

    return size;
}

pub fn get_size(bounds: [4]PointUV) TextureSize {
    const width = bounds[0].distance(bounds[1]);
    const height = bounds[0].distance(bounds[3]);

    const scale = shared.texture_max_size / @max(width, height);
    const ratio = @min(1.0, scale); // makes sure we only downscale
    return TextureSize{ .w = width * ratio, .h = height * ratio };
}

const MAX_COST = 90050924; // it's just chosen base on my own preferences
// returns new safe size, new sigma and cache scale
pub fn get_safe_blur_dims(bounds: [4]PointUV, gaussianBlur: Point) struct { TextureSize, Point, f32 } {
    var size = get_size(bounds);
    const init_width = bounds[0].distance(bounds[1]) * shared.render_scale;
    // * shared.render_scale to revert to logical scale, without impact of camera/zoom

    const init_cache_scale = size.w / init_width;
    var sigma = Point{
        .x = gaussianBlur.x * init_cache_scale,
        .y = gaussianBlur.y * init_cache_scale,
    };

    // Cost control: scale down texture if blur cost is too high
    // in the future would be nice to measure speed of the blur and base on that calculate MAX_COST
    const pixels = size.w * size.h;
    const cost = 3 * sigma.x * pixels + 3 * sigma.y * pixels;

    if (cost > MAX_COST) {
        const scale_down = std.math.pow(f32, cost / MAX_COST, 1.0 / 3.0); // Cube root
        size.w /= scale_down;
        size.h /= scale_down;

        // Scale both texture and sigma proportionally
        sigma.x /= scale_down;
        sigma.y /= scale_down;

        // Verify new cost
        // const new_pixels = size.w * size.h;
        // const new_cost = 3 * sigma_x * new_pixels + 3 * sigma_y * new_pixels;
        // std.debug.print("prev cost: {d}\n new cost: {d}\n   target: {d}\n", .{ cost, new_cost, MAX_COST });
    }

    return .{ size, sigma, size.w / init_width };
}
