const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const consts = @import("../consts.zig");
const std = @import("std");
const fonts = @import("fonts.zig");
const chars = @import("chars.zig");
const utils = @import("../utils.zig");
const triangles = @import("../triangles.zig");
const rects = @import("../rects.zig");
const shared = @import("../shared.zig");
const lines = @import("../lines.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;
const sdf_drawing = @import("../sdf/drawing.zig");
const asset_props = @import("../asset_props.zig");
const fill = @import("../sdf/fill.zig");
const typography_props = @import("typography_props.zig");
const js_glue = @import("../js_glue.zig");
const sdf_effect = @import("../sdf/effect.zig");

const ENTER_CHAR_CODE: u21 = 0xa;
const SOFT_BREAK_MARKER: u21 = 0x2060;

pub const CharVertex = struct {
    relative_bounds: [4]PointUV,
    char: ?u21,
    origin: Point, // origin of the char (bottom left corner), useful for drawing selection/caret/picking
    last_in_line: bool = false,

    pub fn getDrawBounds(self: CharVertex, effects_padding_world: f32, ch_sdf_tex: sdf_drawing.SdfTex, matrix: Matrix3x3) [6]PointUV {
        var bounds: [4]PointUV = undefined;

        for (self.relative_bounds, 0..) |p, i| {
            bounds[i] = matrix.getUV(p);
        }

        // shape.sdf_size includes effects padding, safety padding and rounding error
        // to be able to compare them(obtain scale) together we have to calculate
        // world size -> bounds size + effects padding
        // sdf size -> shape.sdf_size - effects padding - rounding error

        const world_width = bounds[0].distance(bounds[1]) + 2 * effects_padding_world;

        // We assume all sdf texture keeps aspect ratio, just sdf_rounding_err breakes their aspect ratio

        const sdf_world_width = ch_sdf_tex.size.w - (2 * consts.SDF_SAFE_PADDING + ch_sdf_tex.round_err.x);
        const scale_world_vs_sdf = world_width / sdf_world_width;
        const padding_world = effects_padding_world + consts.SDF_SAFE_PADDING * scale_world_vs_sdf;

        const scaled_sdf_round_err = Point{
            .x = ch_sdf_tex.round_err.x * scale_world_vs_sdf,
            .y = ch_sdf_tex.round_err.y * scale_world_vs_sdf,
        };

        return sdf_drawing.getDrawBoundsWorld(
            bounds,
            padding_world,
            Point{ .x = 0, .y = 0 },
            scaled_sdf_round_err,
        );
    }
};

pub const ComputeTextResult = struct {
    content: []const u8,
    selection_start: usize,
    selection_end: usize,
};

pub const Text = struct {
    id: u32,
    content: []const u8,
    bounds: [4]PointUV,
    text_vertex: std.ArrayList(CharVertex),

    sdf_tex: ?sdf_drawing.SdfTex = null,

    props: asset_props.Props,
    effects: std.ArrayList(sdf_effect.Effect),
    typo_props: typography_props.Props,

    pub fn new(
        allocator: std.mem.Allocator,
        id: u32,
        content: []const u8,
        bounds: [4]PointUV,
        props: asset_props.Props,
        input_effects: []const sdf_effect.Serialized,
        input_typo_props: typography_props.Serialized,
        sdf_texture_id: ?u32,
    ) !Text {
        var text = Text{
            .id = id,
            .content = try allocator.dupe(u8, content),
            .typo_props = typography_props.deserialize(input_typo_props),
            .bounds = bounds,
            .text_vertex = std.ArrayList(CharVertex).init(allocator),
            .props = props,
            .effects = try sdf_effect.deserialize(input_effects, allocator),
            .sdf_tex = if (sdf_texture_id) |sdf_tex_id| sdf_drawing.SdfTex{ .id = sdf_tex_id } else null,
        };

        _ = try text.computeText(0, 0);

        try chars.requestCharsSdfs(text);

        return text;
    }

    fn getDrawRelativeBounds(self: Text, x: f32, y: f32, width: f32, height: f32, origin: Point) [4]PointUV {
        const size = self.typo_props.font_size;
        const w = width * size;
        const h = height * size;
        const p = Point{
            .x = origin.x + x * size,
            .y = origin.y + y * size,
        };
        return [_]PointUV{
            .{ .x = p.x, .y = p.y + h, .u = 0.0, .v = 1.0 },
            .{ .x = p.x + w, .y = p.y + h, .u = 1.0, .v = 1.0 },
            .{ .x = p.x + w, .y = p.y, .u = 1.0, .v = 0.0 },
            .{ .x = p.x, .y = p.y, .u = 0.0, .v = 0.0 },
        };
    }

    pub fn computeText(
        self: *Text,
        selection_start: usize,
        selection_end: usize,
    ) !ComputeTextResult {
        if (!fonts.fonts.contains(self.typo_props.font_family_id)) {
            return .{
                .content = self.content,
                .selection_start = 0,
                .selection_end = 0,
            };
        }

        var updated_content = std.ArrayList(u21).init(std.heap.page_allocator);

        self.text_vertex.clearAndFree();

        const lh = self.typo_props.font_size * self.typo_props.line_height;
        const max_text_width = self.bounds[0].distance(self.bounds[1]);
        var longest_line: f32 = 0.0;
        var next_pos = Point{ .x = 0, .y = -lh };

        var new_selection_start: usize = 0;
        var new_selection_end: usize = 0;
        // start of the very first char(bottom left corner of the char)

        var iter = (try std.unicode.Utf8View.init(self.content)).iterator();
        var cp_index: usize = 0;
        var option_prev_cp: ?u21 = null;
        var min_y = -lh;

        while (iter.nextCodepoint()) |cp| { // code point
            defer {
                cp_index += 1;
                option_prev_cp = cp;
            }

            const is_soft_break = cp == SOFT_BREAK_MARKER or (option_prev_cp == SOFT_BREAK_MARKER and cp == ENTER_CHAR_CODE);
            if (is_soft_break) continue;

            // cp_index >= selection -> to put caret on a first free position,
            // because selection_start might be position of SOFT_BREAK_MARKER)
            if (new_selection_start == 0 and cp_index >= selection_start) new_selection_start = self.text_vertex.items.len;
            if (new_selection_end == 0 and cp_index >= selection_end) new_selection_end = self.text_vertex.items.len;

            const char_details = try fonts.get(self.typo_props.font_family_id, cp);
            const char_width = (char_details.x + char_details.width) * self.typo_props.font_size;

            var space_before = if (option_prev_cp) |prev_cp| b: {
                const kerning = try fonts.getKerning(self.typo_props.font_family_id, prev_cp, cp);
                break :b kerning * self.typo_props.font_size;
            } else 0.0;

            const exceeded_max_width = (next_pos.x + space_before + char_width) > max_text_width;

            if (cp == ENTER_CHAR_CODE or exceeded_max_width) {
                next_pos = Point{ .x = 0, .y = next_pos.y - lh };
                space_before = 0.0; // we start with a new line, so no kerning needed
                if (self.text_vertex.items.len > 0) {
                    var previous = &self.text_vertex.items[self.text_vertex.items.len - 1];
                    previous.last_in_line = true;
                }
            }

            if (exceeded_max_width) {
                try updated_content.append(SOFT_BREAK_MARKER);
                try self.text_vertex.append(CharVertex{
                    .relative_bounds = self.getDrawRelativeBounds(0, 0, 0, 0, next_pos),
                    .origin = next_pos,
                    .char = null,
                });

                // add word joiner character before line break so that when user copies the text, they get the same line breaks
                try updated_content.append(ENTER_CHAR_CODE);
                try self.text_vertex.append(CharVertex{
                    .relative_bounds = self.getDrawRelativeBounds(0, 0, 0, 0, next_pos),
                    .origin = next_pos,
                    .char = null,
                });
            }

            const relative_bounds = self.getDrawRelativeBounds(
                char_details.x,
                char_details.y,
                char_details.width,
                char_details.height,
                .{
                    .x = next_pos.x + space_before,
                    .y = next_pos.y,
                },
            );

            // Encode the Unicode codepoint as UTF-8 bytes
            try updated_content.append(cp);
            try self.text_vertex.append(CharVertex{
                .relative_bounds = relative_bounds,
                .char = cp,
                .origin = next_pos,
                .last_in_line = cp == ENTER_CHAR_CODE,
            });

            next_pos.x += space_before + char_width;
            longest_line = @max(longest_line, next_pos.x);
            min_y = @min(min_y, relative_bounds[3].y);
        }

        if (self.text_vertex.items.len > 0) {
            var previous = &self.text_vertex.items[self.text_vertex.items.len - 1];
            previous.last_in_line = true;
        }

        // handle case when caret is behind the last character
        if (cp_index == selection_start)
            new_selection_start = self.text_vertex.items.len;

        if (cp_index == selection_end)
            new_selection_end = self.text_vertex.items.len;

        const text_width = @max(max_text_width, longest_line);
        const matrix = Matrix3x3.getMatrixFromRectangleNoScale(self.bounds);
        self.bounds = [_]PointUV{
            matrix.getUV(.{ .x = 0, .y = 0, .u = 0.0, .v = 1.0 }),
            matrix.getUV(.{ .x = text_width, .y = 0, .u = 1.0, .v = 1.0 }),
            matrix.getUV(.{ .x = text_width, .y = min_y, .u = 1.0, .v = 0.0 }),
            matrix.getUV(.{ .x = 0, .y = min_y, .u = 0.0, .v = 0.0 }),
        };

        var updated_content_bytes = std.ArrayList(u8).init(std.heap.page_allocator);
        const codepoints_slice = try updated_content.toOwnedSlice();
        defer std.heap.page_allocator.free(codepoints_slice);

        for (codepoints_slice) |cp| {
            var utf8_buffer: [4]u8 = undefined;
            const utf8_len = try std.unicode.utf8Encode(cp, &utf8_buffer);
            try updated_content_bytes.appendSlice(utf8_buffer[0..utf8_len]);
        }

        std.heap.page_allocator.free(self.content); // free previous content
        self.content = try updated_content_bytes.toOwnedSlice();

        // self.is_sdf_outdated = true;

        return .{
            .content = self.content,
            .selection_start = new_selection_start,
            .selection_end = new_selection_end,
        };
    }

    pub fn addTextSelectionDrawVertex(
        self: Text,
        ch_vertex: CharVertex,
    ) [2]triangles.DrawInstance {
        const matrix = Matrix3x3.getMatrixFromRectangleNoScale(self.bounds);
        var buffer: [2]triangles.DrawInstance = undefined;
        rects.getDrawVertexData(
            &buffer,
            matrix,
            ch_vertex.origin.x,
            ch_vertex.origin.y,
            ch_vertex.relative_bounds[1].x - ch_vertex.origin.x,
            self.typo_props.font_size * self.typo_props.line_height,
            0.0,
            .{ 0, 100, 100, 100 },
        );
        return buffer;
    }

    pub fn getCaretIndex(self: Text, id: [4]u32, relative_x: f32) ?u32 {
        var caret_index = id[1];
        if (caret_index > 0) {
            const char_details = self.text_vertex.items[caret_index - 1];

            // calculate if the click happened more on left side of the char, in this case put caret before the char, not after
            const left_side = @abs(relative_x - char_details.relative_bounds[0].x) < @abs(relative_x - char_details.relative_bounds[1].x);
            if (left_side) {
                caret_index -= 1;
            }

            return caret_index;
        }

        return null;
    }

    // pub fn getSdfTex(self: *Text) sdf_drawing.SdfTex {
    //     return if (self.sdf_tex) |sdf_tex| sdf_tex else b: {
    //         const sdf_tex = sdf_drawing.SdfTex{
    //             .id = js_glue.createSdfTexture(),
    //         };
    //         self.sdf_tex = sdf_tex;
    //         break :b sdf_tex;
    //     };
    // }

    pub fn addPickVertex(
        self: Text,
        allocator: std.mem.Allocator,
        overflow_size: f32,
    ) ![]triangles.PickInstance {
        var triangles_buffer = std.ArrayList(triangles.PickInstance).init(allocator);
        const matrix = Matrix3x3.getMatrixFromRectangleNoScale(self.bounds);
        const text_width = self.bounds[1].distance(self.bounds[0]);
        const text_height = self.bounds[3].distance(self.bounds[0]);

        // above text area
        const area_above_text_buffer = rects.getPickVertexData(
            matrix,
            -overflow_size,
            0,
            text_width + 2 * overflow_size,
            overflow_size,
            0.0,
            .{ self.id, 1, 0, 0 },
        );
        try triangles_buffer.appendSlice(&area_above_text_buffer);

        // below text area
        const area_below_text_buffer = rects.getPickVertexData(
            matrix,
            -overflow_size,
            -text_height,
            text_width + 2 * overflow_size,
            -overflow_size,
            0.0,
            .{ self.id, self.text_vertex.items.len + 1, 0, 0 },
        );
        try triangles_buffer.appendSlice(&area_below_text_buffer);

        var next_char_is_first_in_line = true;
        for (self.text_vertex.items, 0..) |vertex, index| {
            const half_width = (vertex.relative_bounds[1].x - vertex.origin.x) / 2;
            if (half_width > consts.EPSILON) {
                const valid_pick_index = index + 1; // pick = 0 -> no selection
                // left part of the char
                const left_additional_offset =
                    if (next_char_is_first_in_line) overflow_size else 0.0;
                try triangles_buffer.appendSlice(&rects.getPickVertexData(
                    matrix,
                    vertex.origin.x - left_additional_offset,
                    vertex.origin.y,
                    half_width + left_additional_offset,
                    self.typo_props.line_height * self.typo_props.font_size,
                    0.0,
                    .{ self.id, valid_pick_index, 0, 0 },
                ));

                // right part of the char
                const char_x = vertex.origin.x + half_width;
                const right_space = text_width - (char_x + half_width); // space between char right edge and text right edge
                const right_additional_offset =
                    if (vertex.last_in_line) right_space + overflow_size else 0;

                try triangles_buffer.appendSlice(&rects.getPickVertexData(
                    matrix,
                    char_x,
                    vertex.origin.y,
                    half_width + right_additional_offset,
                    self.typo_props.line_height * self.typo_props.font_size,
                    0.0,
                    .{ self.id, valid_pick_index + 1, 0, 0 },
                ));

                next_char_is_first_in_line = vertex.last_in_line;
            }
        }

        return triangles_buffer.toOwnedSlice();
    }

    pub fn getDrawUniform(self: Text, effects: sdf_effect.Effect, sdf_scale: f32) sdf_drawing.DrawUniform {
        return sdf_drawing.getDrawUniform(
            effects,
            sdf_scale,
            self.props.opacity,
        );
    }

    pub fn serialize(self: Text, allocator: std.mem.Allocator) !Serialized {
        var effects_list = std.ArrayList(sdf_effect.Serialized).init(allocator);
        for (self.effects.items) |effect| {
            try effects_list.append(sdf_effect.Serialized{
                .dist_start = effect.dist_start,
                .dist_end = effect.dist_end,
                .fill = try effect.fill.serialize(allocator),
            });
        }

        return Serialized{
            .id = self.id,
            .content = self.content,
            .bounds = self.bounds,
            .props = self.props,
            .effects = try effects_list.toOwnedSlice(),
            .typo_props = self.typo_props.serialize(),
            .sdf_texture_id = if (self.sdf_tex) |tex| tex.id else null,
            .is_sdf_shared = self.sdf_tex != null,
        };
    }

    pub fn deinit(self: *Text) void {
        std.heap.page_allocator.free(self.content);
        self.text_vertex.deinit();
        sdf_effect.deinit(self.effects);
    }
};

pub const Serialized = struct {
    id: u32,
    content: ?[]const u8, // it's a null pointer exception for case when content is empty, we allow null
    // to avoid throwing the exception by Zigar
    bounds: [4]PointUV,
    props: asset_props.Props,
    effects: []sdf_effect.Serialized,
    typo_props: typography_props.Serialized,
    sdf_texture_id: ?u32,
    is_sdf_shared: bool,

    pub fn compare(self: Serialized, other: Serialized) bool {
        const all_match = self.id == other.id and
            self.props.compare(other.props) and
            self.is_sdf_shared == other.is_sdf_shared and
            utils.compareBounds(self.bounds, other.bounds) and
            self.typo_props.compare(other.typo_props) and
            sdf_effect.compareSerialized(self.effects, other.effects) and
            std.mem.eql(u8, self.content orelse &.{}, other.content orelse &.{});

        return all_match;
    }
};
