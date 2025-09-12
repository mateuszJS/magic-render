const std = @import("std");
const Point = @import("../types.zig").Point;

pub const Details = struct {
    sdf_texture_id: u32,
    width: f32,
    height: f32,
    points: []const Point,
    outdated_sdf: bool,
};

// const DEFAULT_DETAILS = Details{
//     .sdf_texture_id = 0,
//     .width = 0,
//     .height = 0,
//     .paths = &.{},
//     .is_outdated = false,
// };

pub const Chars = struct {
    chars: std.AutoArrayHashMap(u8, Details),

    pub fn new() Chars {
        return Chars{
            .chars = std.AutoArrayHashMap(u8, Details).init(std.heap.page_allocator),
        };
    }

    pub fn get(self: Chars, c: u8) ?Details {
        return self.chars.get(c);
    }

    pub fn set(self: *Chars, c: u8, details: Details) !void {
        return try self.chars.put(c, details);
    }
};
