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
    var width = bounds[0].distance(bounds[1]);
    var height = bounds[0].distance(bounds[3]);

    if (width > shared.texture_max_size) {
        const ratio = shared.texture_max_size / width;
        width = shared.texture_max_size;
        height *= ratio;
    }

    if (height > shared.texture_max_size) {
        const ratio = shared.texture_max_size / height;
        height = shared.texture_max_size;
        width *= ratio;
    }

    return TextureSize{ .w = width, .h = height };
}

const MAX_COST = 90050924; // it's just chosen base on my own preferences
// returns new safe size and new sigma
pub fn get_safe_blur_dims(tex_size: TextureSize, scaled_sigma: Point) struct { TextureSize, Point } {

    // Cost control: scale down texture if blur cost is too high
    var new_sigma = Point{ .x = scaled_sigma.x, .y = scaled_sigma.y };
    // in the future would be nice to measure speed of the blur and base on that calculate MAX_COST
    var new_tex_size = TextureSize{ .w = tex_size.w, .h = tex_size.h };
    const pixels = tex_size.w * tex_size.h;
    const cost = 3 * new_sigma.x * pixels + 3 * new_sigma.y * pixels;

    if (cost > MAX_COST) {
        const scale_down = std.math.pow(f32, cost / MAX_COST, 1.0 / 3.0); // Cube root
        new_tex_size.w /= scale_down;
        new_tex_size.h /= scale_down;

        // Scale both texture and sigma proportionally
        new_sigma.x /= scale_down;
        new_sigma.y /= scale_down;

        // Verify new cost
        // const new_pixels = size.w * size.h;
        // const new_cost = 3 * sigma_x * new_pixels + 3 * sigma_y * new_pixels;
        // std.debug.print("prev cost: {d}\n new cost: {d}\n   target: {d}\n", .{ cost, new_cost, MAX_COST });
    }

    return .{ new_tex_size, new_sigma };
}
