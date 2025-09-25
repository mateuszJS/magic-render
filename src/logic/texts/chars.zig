const std = @import("std");
const Point = @import("../types.zig").Point;

pub const Details = struct {
    sdf_texture_id: ?u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    max_requested_effect_padding: f32,
    max_requested_font_size: f32,
    points: []const Point,
    outdated_sdf: bool,
    kerning: std.AutoArrayHashMap(u21, f32), // kerning between current char and next one

    paths_container_width: f32 = 0,
    paths_container_height: f32 = 0,
    effect_padding: f32 = 0,
    sdf_scale: f32 = 1,
};

pub const Chars = struct {
    chars: std.AutoArrayHashMap(u21, Details),

    pub fn new() Chars {
        return Chars{
            .chars = std.AutoArrayHashMap(u21, Details).init(std.heap.page_allocator),
        };
    }

    pub fn get(self: *Chars, c: u21) ?*Details {
        return self.chars.getPtr(c);
    }

    pub fn set(self: *Chars, c: u21, details: Details) !void {
        return try self.chars.put(c, details);
    }
};
