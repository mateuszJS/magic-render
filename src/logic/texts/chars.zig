const std = @import("std");
const Point = @import("../types.zig").Point;
const shared = @import("../shared.zig");
const consts = @import("../consts.zig");
const utils = @import("../utils.zig");

const MIN_SDF_FONT_SIZE = 50; // below that we lose too many details
// in SDF textures

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
    // this one is relative to requested viewport size, not world size.
    // It's due to the fact char's sdf is used for multiple cases at once
    // so there is no one world case size to use
    // so sdf_scale is always 1 expect fact when sdf texture hits max size!

    max_requested_world_font_size: f32 = 0,
    max_font_size: f32 = 0,
    max_ratio_padding_to_font_size: f32 = 0,

    pub fn request_size(self: *Details, font_size: f32, raw_effect_padding: f32) void {
        const next_ep = utils.getNextStep(MIN_SDF_FONT_SIZE, raw_effect_padding);

        if (consts.EPSILON + self.max_ratio_padding_to_font_size < next_ep / font_size) {
            std.debug.print("1 requesting char: {d} {d}\n", .{ font_size, next_ep });
            self.max_ratio_padding_to_font_size = next_ep / font_size;
            self.outdated_sdf = true;
        }

        const viewport_font_size = font_size / shared.render_scale;
        const next_fs = utils.getNextStep(MIN_SDF_FONT_SIZE, viewport_font_size);
        if (next_fs > self.max_requested_world_font_size + consts.EPSILON) {
            std.debug.print("2 requesting char: {d} {d}\n", .{ self.max_requested_world_font_size, next_fs });
            self.max_requested_world_font_size = next_fs;
            self.max_font_size = next_fs * shared.render_scale;
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
