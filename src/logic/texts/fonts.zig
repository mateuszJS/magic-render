const std = @import("std");
const chars = @import("chars.zig");
const Point = @import("../types.zig").Point;
const js_glue = @import("../js_glue.zig");

pub var fonts: std.AutoArrayHashMap(u32, chars.Chars) = undefined;

pub fn init() void {
    fonts = std.AutoArrayHashMap(u32, chars.Chars).init(std.heap.page_allocator);
}

// struct "Details" is owned by allocator, ArrayHashMap only has a pointer, but doesn't own the struct!
// So pointer to a "Details" struct should never change!
pub fn get(font_id: u32, c: u21) !*chars.Details {
    const font = fonts.getPtr(font_id) orelse @panic("Font ID not found");
    const details = font.getChar(c);
    if (details) |d| {
        return d;
    } else {
        const char = js_glue.getCharData(font_id, c);

        const d = try std.heap.page_allocator.create(chars.Details);
        std.debug.print("NEW DETIAILS {u} {d} {?}\n", .{ c, c, char.sdf_texture_id });
        d.* = chars.Details{
            .sdf_texture_id = char.sdf_texture_id,
            .x = char.x,
            .y = char.y,
            .width = char.width,
            .height = char.height,
            .points = char.points,
            .outdated_sdf = true,
            .kerning = std.AutoArrayHashMap(u21, f32).init(std.heap.page_allocator),
        };
        try font.addChar(c, d);
        // Now get the pointer to the stored struct
        return font.getChar(c) orelse @panic("Failed to retrieve stored character details");
    }
}

pub fn getKerning(font_id: u32, c1: u21, c2: u21) !f32 {
    var details = try get(font_id, c1);
    if (details.kerning.get(c2)) |k| {
        return k;
    } else {
        const k = js_glue.getKerning(font_id, c1, c2);
        try details.kerning.put(c2, k);
        return k;
    }
}

pub fn new(font_id: u32) !void {
    const ch = chars.Chars.new();
    return try fonts.put(font_id, ch);
}
