const PointUV = @import("types.zig").PointUV;
const shared = @import("shared.zig");

pub const TextureSize = struct {
    w: f32,
    h: f32,
};

pub fn get_sdf_size(bounds: [4]PointUV) TextureSize {
    var size = get_size(bounds);

    const sdf_texture_size = size.w * size.w * 16;
    if (sdf_texture_size > shared.max_buffer_size) {
        const max_pixels = shared.max_buffer_size / 16.0;
        const ratio = @sqrt(max_pixels / (size.w * size.h));
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
