const std = @import("std");
const chars = @import("chars.zig");
const Point = @import("../types.zig").Point;

pub const SerializedCharDetails = struct {
    points: []const Point = &.{},
    width: f32,
    height: f32,
    sdf_texture_id: u32,

    pub fn setPaths(self: *SerializedCharDetails, points: []const Point) !void {
        self.points = try std.heap.page_allocator.dupe(Point, points);
    }
};

pub var getCharData: *const fn (u32, u8) SerializedCharDetails = undefined;

pub var fonts: std.AutoArrayHashMap(u32, chars.Chars) = undefined;

pub fn init() void {
    fonts = std.AutoArrayHashMap(u32, chars.Chars).init(std.heap.page_allocator);
}

pub fn get(font_id: u32, c: u8) !chars.Details {
    const f = fonts.getPtr(font_id) orelse @panic("Font ID not found");
    const details = f.get(c);
    if (details) |d| {
        return d;
    } else {
        const char = getCharData(font_id, c);
        const d = chars.Details{
            .sdf_texture_id = char.sdf_texture_id,
            .width = char.width,
            .height = char.height,
            .points = char.points,
            .outdated_sdf = true,
        };
        try f.set(c, d);
        // return d;
        return f.get(c) orelse @panic("Failed to get char after setting it");
    }
}

pub fn new(font_id: u32) !void {
    const ch = chars.Chars.new();
    return try fonts.put(font_id, ch);
}

// pub fn set(font_id: u32, c: u8, details: font.Details) void {
//     return fonts.put(font_id, f);
// }
