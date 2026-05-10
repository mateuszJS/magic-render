const std = @import("std");
const chars = @import("chars.zig");
const Point = @import("../types.zig").Point;
const js_glue = @import("../js_glue.zig");
const sdf_drawing = @import("../sdf/drawing.zig");

pub const DEFAULT_FONT_ID: u32 = 0;

pub var isReady: bool = false; // indicate if at least default font is loaded, if not then we should avoid requesting any data

pub var fonts: std.AutoArrayHashMap(u32, chars.Chars) = undefined;

pub fn init() void {
    fonts = std.AutoArrayHashMap(u32, chars.Chars).init(std.heap.page_allocator);
}

// struct "Details" is owned by allocator, ArrayHashMap only has a pointer, but doesn't own the struct!
// So pointer to a "Details" struct should never change!
pub fn get(_font_id: u32, c: u21) !*chars.Details {
    const safe_font_id = if (fonts.contains(_font_id)) _font_id else DEFAULT_FONT_ID;

    const font = fonts.getPtr(safe_font_id) orelse @panic("Font ID not found");
    const details = font.getChar(c);
    if (details) |d| {
        return d;
    } else {
        const char = js_glue.getCharData(safe_font_id, c);
        const d = try std.heap.page_allocator.create(chars.Details);
        d.* = chars.Details{
            .sdf_tex = if (char.sdf_texture_id) |sdf_tex_id| sdf_drawing.SdfTex{ .id = sdf_tex_id } else null,
            .x = char.x,
            .y = char.y,
            .width = char.width,
            .height = char.height,
            .paths = char.paths,
            .kerning = std.AutoArrayHashMap(u21, f32).init(std.heap.page_allocator),
        };
        try font.addChar(c, d);
        // Now get the pointer to the stored struct
        return font.getChar(c) orelse @panic("Failed to retrieve stored character details");
    }
}

pub fn getKerning(_font_id: u32, c1: u21, c2: u21) !f32 {
    const safe_font_id = if (fonts.contains(_font_id)) _font_id else DEFAULT_FONT_ID;
    var details = try get(safe_font_id, c1);
    if (details.kerning.get(c2)) |k| {
        return k;
    } else {
        const k = js_glue.getKerning(safe_font_id, c1, c2);
        try details.kerning.put(c2, k);
        return k;
    }
}

pub fn new(font_id: u32) !void {
    if (font_id == DEFAULT_FONT_ID) {
        isReady = true;
    }

    const ch = chars.Chars.new();
    return try fonts.put(font_id, ch);
}
