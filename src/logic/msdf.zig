const IconData = @import("types.zig").IconData;

pub fn get_msdf_vertex_data(icon: IconData, x: f32, y: f32, scale: f32) [36]f32 {
    const dest_y_top = y + icon.real_height * scale;
    const dest_y_bottom = y;
    const dest_x_left = x;
    const dest_x_right = x + icon.real_width * scale;

    const source_y_top = 1.0 - icon.y;
    const source_y_bottom = 1.0 - (icon.y + icon.height);
    const source_x_left = icon.x;
    const source_x_right = icon.x + icon.width;

    return [_]f32{
        dest_x_left,  dest_y_bottom, 0.0, 1.0, source_x_left,  source_y_bottom,
        dest_x_left,  dest_y_top,    0.0, 1.0, source_x_left,  source_y_top,
        dest_x_right, dest_y_top,    0.0, 1.0, source_x_right, source_y_top,
        // second triangle
        dest_x_right, dest_y_top,    0.0, 1.0, source_x_right, source_y_top,
        dest_x_right, dest_y_bottom, 0.0, 1.0, source_x_right, source_y_bottom,
        dest_x_left,  dest_y_bottom, 0.0, 1.0, source_x_left,  source_y_bottom,
    };
}
