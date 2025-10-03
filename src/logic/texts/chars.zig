const std = @import("std");
const Point = @import("../types.zig").Point;
const shared = @import("../shared.zig");
const consts = @import("../consts.zig");

pub const Details = struct {
    sdf_texture_id: ?u32,
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    points: []const Point,
    outdated_sdf: bool,
    kerning: std.AutoArrayHashMap(u21, f32), // kerning between current char and next one

    sdf_scale: f32 = 1, // in contrary to other sdf_scales
    // this one is relative to requested viewport size, not logical size.
    // It's due to the fact char's sdf is used for multiple cases at once
    // so there is no one logical size to base on
    // so sdf_scale is always 1 expect fact when sdf texture hits max size!

    max_requested_viewport_font_size: f32 = 0,
    max_font_size: f32 = 0,
    max_ratio_padding_to_font_size: f32 = 0,

    pub fn request_size(self: *Details, font_size: f32, effect_padding: f32) void {
        if (self.max_ratio_padding_to_font_size < effect_padding / font_size) {
            self.max_ratio_padding_to_font_size = effect_padding / font_size;
            self.outdated_sdf = true;
        }

        const viewport_font_size = font_size / shared.render_scale;
        if (viewport_font_size > self.max_requested_viewport_font_size) {
            self.max_requested_viewport_font_size = viewport_font_size; // is override while we compute sdfs
            // since shared.render_scale might change between request and sdf computation
            self.max_font_size = font_size;
            self.outdated_sdf = true;
        }
    }
};

pub const Chars = struct {
    chars: std.AutoArrayHashMap(u21, *Details),

    pub fn new() Chars {
        return Chars{
            .chars = std.AutoArrayHashMap(u21, *Details).init(std.heap.page_allocator),
        };
    }

    pub fn getChar(self: *Chars, c: u21) ?*Details {
        return self.chars.get(c);
    }

    pub fn addChar(self: *Chars, c: u21, details: *Details) !void {
        return try self.chars.put(c, details);
    }
};
