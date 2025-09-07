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

const MAX_FILTER_RADIUS = 128.0 - 2.0; // 2.0 just to avoid being on the edge of floating
// point precision during later computations
pub fn within_max_blur_size(tex_size: TextureSize, blur_size: Point, scale: f32) TextureSize {
    const sigma_x = blur_size.x * scale;
    const sigma_y = blur_size.y * scale;
    const filter_size_x = @max(1.0, 2.0 * @ceil(3 * sigma_x) + 1.0);
    const filter_size_y = @max(1.0, 2.0 * @ceil(3 * sigma_y) + 1.0);
    const filter_size_max = @max(filter_size_x, filter_size_y);

    if (filter_size_max > MAX_FILTER_RADIUS) {
        const ratio = MAX_FILTER_RADIUS / filter_size_max;
        return TextureSize{
            .w = tex_size.w * ratio,
            .h = tex_size.h * ratio,
        };
    }

    return tex_size;
}

// Calculate the blur radius in pixels for padding calculation
// Returns the maximum distance the blur can extend in each direction
pub fn get_blur_radius_pixels(blur_size: Point, scale: f32) Point {
    const sigma_x = blur_size.x * scale;
    const sigma_y = blur_size.y * scale;

    // Calculate the effective blur radius (3 * sigma is ~99.7% of the blur effect)
    // Using 3.1 for extra safety margin to ensure no clipping
    const radius_x = 3.1 * sigma_x;
    const radius_y = 3.1 * sigma_y;

    return .{ .x = radius_x, .y = radius_y };
}
