const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;
const shared = @import("shared.zig");
const std = @import("std");

pub const TextureSize = struct {
    w: f32 = 0,
    h: f32 = 0,
};

// iOS WebKit Metal crashes on rgba32float STORAGE_BINDING textures above ~32MB,
// even though WebGPU reports much higher maxBufferSize/maxStorageBufferBindingSize.
const MAX_SDF_TEXTURE_BYTES: f32 = 32 * 1024 * 1024; // 32MB hard cap

// buffer size limits the size of rgba32float texture
pub fn get_allowed_sdf_size(desired_size: TextureSize) TextureSize {
    var size = desired_size;
    const sdf_texture_size = size.w * size.h * 16;

    // const effective_limit = @min(shared.max_buffer_size, MAX_SDF_TEXTURE_BYTES);
    // if (sdf_texture_size > effective_limit) {
    // const max_pixels = effective_limit / 16.0;
    if (sdf_texture_size > shared.max_buffer_size) {
        const max_pixels = shared.max_buffer_size / 16.0;
        const ratio = max_pixels / (size.w * size.h);
        size.w *= ratio;
        size.h *= ratio;
    }

    return size;
}

pub fn get_allowed_size(width: f32, height: f32) TextureSize {
    const scale = shared.texture_max_size / @max(width, height);
    const ratio = @min(1.0, scale); // makes sure we only downscale
    return TextureSize{ .w = width * ratio, .h = height * ratio };
}

const MAX_COST = 90050924; // it's just chosen base on my own preferences
// returns new safe size, new sigma and cache scale
pub fn get_safe_blur_dims(init_width: f32, bounds: [4]PointUV, gaussianBlur: Point) struct { TextureSize, Point, f32 } {
    var size = get_allowed_size(
        bounds[0].distance(bounds[1]),
        bounds[0].distance(bounds[3]),
    );
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
