const Matrix3x3 = @import("./matrix.zig").Matrix3x3;
const std = @import("std");

pub fn getDefaultMatrix(
    tex_width: f32,
    tex_height: f32,
    project_width: f32,
    project_height: f32,
) Matrix3x3 {
    const scale = getDefaultTextureScale(tex_width, tex_height, project_width, project_height);
    const scaled_width = tex_width * scale;
    const scaled_height = tex_height * scale;
    const padding_x = (project_width - scaled_width) * 0.5;
    const padding_y = (project_height - scaled_height) * 0.5;

    return Matrix3x3.from([_]f32{
        scaled_width / tex_width, 0.0,                        padding_x,
        0.0,                      scaled_height / tex_height, padding_y,
        0.0,                      0.0,                        1.0,
    });
}

/// Returns visually pleasant size of texture, to make sure it doesn't overflow canvas but also is not too small to manipulate
fn getDefaultTextureScale(
    tex_width: f32,
    tex_height: f32,
    project_width: f32,
    project_height: f32,
) f32 {
    const height_diff = project_height - tex_height;
    const width_diff = project_width - tex_width;

    if (height_diff < width_diff) {
        const height = std.math.clamp(tex_height, project_height * 0.2, project_height * 0.8);
        return height / tex_height;
    }

    const width = std.math.clamp(tex_width, project_width * 0.2, project_width * 0.8);
    return width / tex_width;
}
