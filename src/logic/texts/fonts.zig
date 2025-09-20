const std = @import("std");
const chars = @import("chars.zig");
const Point = @import("../types.zig").Point;

pub const SerializedCharDetails = struct {
    points: []const Point = &.{},
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    sdf_texture_id: ?u32,

    pub fn setPaths(self: *SerializedCharDetails, points: []const Point) !void {
        self.points =
            if (points.len > 0)
                try std.heap.page_allocator.dupe(Point, points)
            else
                &.{};
    }
};

pub var getCharData: *const fn (u32, u21) SerializedCharDetails = undefined;
pub var getKerning: *const fn (u21, u21) f32 = undefined;

pub var fonts: std.AutoArrayHashMap(u32, chars.Chars) = undefined;

pub fn init() void {
    fonts = std.AutoArrayHashMap(u32, chars.Chars).init(std.heap.page_allocator);
}

pub fn get(font_id: u32, c: u21) !*chars.Details {
    const f = fonts.getPtr(font_id) orelse @panic("Font ID not found");
    const details = f.get(c);
    if (details) |d| {
        return d;
    } else {
        const char = getCharData(font_id, c);
        const d = chars.Details{
            .sdf_texture_id = char.sdf_texture_id,
            .x = char.x,
            .y = char.y,
            .width = char.width,
            .height = char.height,
            .points = char.points,
            .outdated_sdf = true,
            .kerning = std.AutoArrayHashMap(u21, f32).init(std.heap.page_allocator),
        };
        try f.set(c, d);
        // Now get the pointer to the stored struct
        return f.get(c) orelse @panic("Failed to retrieve stored character details");
    }
}

pub fn get_kerning(font_id: u32, c1: u21, c2: u21) !f32 {
    var details = try get(font_id, c1);
    if (details.kerning.get(c2)) |k| {
        return k;
    } else {
        const k = getKerning(c1, c2);
        try details.kerning.put(c2, k);
        return k;
    }
}

pub fn new(font_id: u32) !void {
    const ch = chars.Chars.new();
    return try fonts.put(font_id, ch);
}
