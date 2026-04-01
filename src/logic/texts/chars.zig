const std = @import("std");
const Point = @import("../types.zig").Point;
const shared = @import("../shared.zig");
const consts = @import("../consts.zig");
const utils = @import("../utils.zig");
const TextureSize = @import("../texture_size.zig").TextureSize;
const texts = @import("./texts.zig");
const fonts = @import("./fonts.zig");
const sdf_drawing = @import("../sdf/drawing.zig");

const MIN_SDF_FONT_SIZE = 50; // below that we lose too many details
// in SDF textures

pub const Details = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    points: []const Point,
    outdated_sdf: bool,
    kerning: std.AutoArrayHashMap(u21, f32), // kerning between current char and next one

    sdf_tex: ?sdf_drawing.SdfTex = null,

    max_requested_viewport_font_size: f32 = 0,
    max_ratio_padding_to_font_size: f32 = 0,

    pub fn request_size(self: *Details, font_size: f32, effect_padding: f32) void {
        if (consts.EPSILON + self.max_ratio_padding_to_font_size < effect_padding / font_size) {
            self.max_ratio_padding_to_font_size = effect_padding / font_size;
            self.outdated_sdf = true;
        }

        const font_size_world = font_size / shared.render_scale;
        // const next_font_size = utils.getNextStep(MIN_SDF_FONT_SIZE, font_size_world);
        const next_font_size = font_size_world;
        if (next_font_size > self.max_requested_viewport_font_size + consts.EPSILON) {
            self.max_requested_viewport_font_size = next_font_size;
            // self.max_font_size = next_font_size * shared.render_scale; // I don't think it's needed
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

pub fn requestCharsSdfs(text: texts.Text) !void {
    if (!fonts.fonts.contains(text.typo_props.font_family_id)) return;

    const padding = sdf_drawing.getSdfPadding(text.effects.items);

    for (text.text_vertex.items) |vertex| {
        if (vertex.char) |char| {
            const ch_d = try fonts.get(text.typo_props.font_family_id, char);

            if (ch_d.sdf_tex != null) {
                ch_d.request_size(
                    text.typo_props.font_size,
                    padding,
                );
            }
        }
    }
}
