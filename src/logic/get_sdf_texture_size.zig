const PointUV = @import("types.zig").PointUV;
const TextureSize = @import("types.zig").TextureSize;
const shared = @import("shared.zig");

pub fn get_sdf_texture_size(bounds: [4]PointUV) TextureSize {
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

    const sdf_texture_size = width * height * 16;
    if (sdf_texture_size > shared.max_buffer_size) {
        const max_pixels = shared.max_buffer_size / 16.0;
        const ratio = @sqrt(max_pixels / (width * height));
        width *= ratio;
        height *= ratio;
    }

    return TextureSize{ .w = @intFromFloat(width), .h = @intFromFloat(height) };
}
