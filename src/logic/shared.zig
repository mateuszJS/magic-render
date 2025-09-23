pub var render_scale: f32 = 1.0; // Global render scale
pub var max_buffer_size: f32 = 0; // stores as float only to avoid constant casts
pub var texture_max_size: f32 = 0; // stores as float only to avoid constant casts
pub var time: f32 = 0.0; // time in milliseconds
pub var time_u32: u32 = 0; // time in milliseconds as u32

pub fn setTime(t: f32) void {
    time = t;
    time_u32 = @intFromFloat(t);
}
