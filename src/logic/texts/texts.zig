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

const ENTER_CHAR_CODE: u21 = 0xa;
const SOFT_BREAK_MARKER: u21 = 0x2060;

pub var caret_position: u32 = 0;
pub var selection_end_position: u32 = 0; // selection start is indicated by caret_position
pub var last_caret_update: u32 = 0;

pub const CharVertex = struct {
    relative_bounds: [6]PointUV,
    sdf_texture_id: ?u32,
    origin: Point, // origin of the char (bottom left corner), useful for drawing selection/caret/picking
    last_in_line: bool = false,
};

pub const ComputeTextResult = struct {
    content: []const u8,
    selection_start: usize,
    selection_end: usize,
};

pub const Text = struct {
    id: u32,
    content: []const u8,
    font_size: f32,
    bounds: [4]PointUV,
    line_height: f32 = 1.2, // line height multiplier
    text_vertex: std.ArrayList(CharVertex),
    serialized_updated_content: []const u8 = &.{}, // to cache results of computeText
    // useful when user clicks on text again in the future to be used as input for HTMLTextAreaElement

    pub fn new(
        id: u32,
        content: []const u8,
        bounds: [4]PointUV,
        font_size: f32,
    ) !Text {
        var text = Text{
            .id = id,
            .content = content,
            .font_size = font_size,
            .bounds = bounds,
            .text_vertex = std.ArrayList(CharVertex).init(std.heap.page_allocator),
        };

        _ = try text.computeText(0, 0);

        return text;
    }

    fn getDrawRelativeBounds(self: Text, x: f32, y: f32, width: f32, height: f32, origin: Point) [6]PointUV {
        const w = width * self.font_size;
        const h = height * self.font_size;
        const p = Point{
            .x = origin.x + x * self.font_size,
            .y = origin.y + y * self.font_size,
        };
        return [_]PointUV{
            .{ .x = p.x, .y = p.y, .u = 0.0, .v = 0.0 },
            .{ .x = p.x, .y = p.y + h, .u = 0.0, .v = 1.0 },
            .{ .x = p.x + w, .y = p.y + h, .u = 1.0, .v = 1.0 },
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
        var updated_content = std.ArrayList(u21).init(std.heap.page_allocator);

        self.text_vertex.clearAndFree();
        self.text_vertex.deinit();
        self.text_vertex = std.ArrayList(CharVertex).init(std.heap.page_allocator);

        const lh = self.font_size * self.line_height;
        const max_text_width = self.bounds[0].distance(self.bounds[1]);
        var longest_line: f32 = 0.0;
        var next_pos = Point{ .x = 0, .y = -lh };

        var new_selection_start: usize = 0;
        var new_selection_end: usize = 0;
        // start of the very first char(bottom left corner of the char)

        var iter = (try std.unicode.Utf8View.init(self.content)).iterator();
        var i: isize = -1; // we increase i by 1 on the start so it starts with 0 actually
        var option_prev_cp: ?u21 = null;

        while (iter.nextCodepoint()) |cp| { // code point
            i += 1;

            const is_soft_break = cp == SOFT_BREAK_MARKER or (option_prev_cp == SOFT_BREAK_MARKER and cp == ENTER_CHAR_CODE);
            option_prev_cp = cp;
            if (is_soft_break) continue;

            // i >= selection -> to put caret on a first free position,
            // because selection_start might be position of SOFT_BREAK_MARKER)
            if (new_selection_start == 0 and i >= selection_start) new_selection_start = self.text_vertex.items.len;
            if (new_selection_end == 0 and i >= selection_end) new_selection_end = self.text_vertex.items.len;

            const char_details = try fonts.get(0, cp);
            const char_width = (char_details.x + char_details.width) * self.font_size;

            var space_before = if (option_prev_cp) |prev_cp| b: {
                const kerning = try fonts.get_kerning(0, prev_cp, cp);
                break :b kerning * self.font_size;
            } else 0.0;

            const exceeded_max_width = (next_pos.x + space_before + char_width) > max_text_width;
            if (exceeded_max_width) {
                if (self.text_vertex.items.len > 0) {
                    var previous = &self.text_vertex.items[self.text_vertex.items.len - 1];
                    previous.last_in_line = true;
                }

                try updated_content.append(SOFT_BREAK_MARKER);
                try self.text_vertex.append(CharVertex{
                    .relative_bounds = self.getDrawRelativeBounds(0, 0, 0, 0, next_pos),
                    .sdf_texture_id = null,
                    .origin = next_pos,
                });

                // add word joiner character before line break so that when user copies the text, they get the same line breaks
                try updated_content.append(ENTER_CHAR_CODE);
                try self.text_vertex.append(CharVertex{
                    .relative_bounds = self.getDrawRelativeBounds(0, 0, 0, 0, next_pos),
                    .sdf_texture_id = null,
                    .origin = next_pos,
                });

                next_pos = Point{ .x = 0, .y = next_pos.y - lh };
                space_before = 0.0; // we start with a new line, so no kerning needed
            }

            const cd = try fonts.get(0, cp); // char details

            const relative_bounds = self.getDrawRelativeBounds(cd.x, cd.y, cd.width, cd.height, .{
                .x = next_pos.x + space_before,
                .y = next_pos.y,
            });

            // Encode the Unicode codepoint as UTF-8 bytes
            try updated_content.append(cp);
            try self.text_vertex.append(CharVertex{
                .relative_bounds = relative_bounds,
                .sdf_texture_id = cd.sdf_texture_id,
                .origin = next_pos,
                .last_in_line = cp == ENTER_CHAR_CODE,
            });

            if (cp == ENTER_CHAR_CODE) {
                next_pos = Point{ .x = 0, .y = next_pos.y - lh };
            }

            next_pos.x += space_before + char_width;
            longest_line = @max(longest_line, next_pos.x);
        }

        if (self.text_vertex.items.len > 0) {
            var previous = &self.text_vertex.items[self.text_vertex.items.len - 1];
            previous.last_in_line = true;
        }

        // handle case when caret is behind the last character
        if (i + 1 == selection_start)
            new_selection_start = self.text_vertex.items.len;

        if (i + 1 == selection_end)
            new_selection_end = self.text_vertex.items.len;

        const text_width = @max(max_text_width, longest_line);
        const matrix = Matrix3x3.getMatrixFromRectangleNoScale(self.bounds);

        self.bounds = [_]PointUV{
            matrix.getUV(.{ .x = 0, .y = 0, .u = 0.0, .v = 1.0 }),
            matrix.getUV(.{ .x = text_width, .y = 0, .u = 1.0, .v = 1.0 }),
            matrix.getUV(.{ .x = text_width, .y = next_pos.y, .u = 1.0, .v = 0.0 }),
            matrix.getUV(.{ .x = 0, .y = next_pos.y, .u = 0.0, .v = 0.0 }),
        };

        var serialized_updated_content = std.ArrayList(u8).init(std.heap.page_allocator);
        for (try updated_content.toOwnedSlice()) |cp| {
            var utf8_buffer: [4]u8 = undefined;
            const utf8_len = try std.unicode.utf8Encode(cp, &utf8_buffer);
            try serialized_updated_content.appendSlice(utf8_buffer[0..utf8_len]);
        }

        self.serialized_updated_content = try serialized_updated_content.toOwnedSlice();

        return .{
            .content = self.serialized_updated_content,
            .selection_start = new_selection_start,
            .selection_end = new_selection_end,
        };
    }

    pub fn addTextSelectionDrawVertex(
        triangles_buffer: *std.ArrayList(triangles.DrawInstance),
        matrix: Matrix3x3,
        start: Point,
        width: f32,
        height: f32,
    ) !void {
        var buffer: [2]triangles.DrawInstance = undefined;
        rects.getDrawVertexData(
            &buffer,
            matrix,
            start.x,
            start.y,
            width,
            height,
            0.0,
            .{ 0, 50, 50, 50 },
        );
        try triangles_buffer.appendSlice(&buffer);
    }

    pub fn addCaretDrawVertex(
        triangles_buffer: *std.ArrayList(triangles.DrawInstance),
        position: Point,
        height: f32,
        time_u32: u32,
    ) !void {
        const CARET_BLINK_INTERVAL_MS = 700;
        const blink = (time_u32 / CARET_BLINK_INTERVAL_MS) % 2 == 0;
        const newly_updated = time_u32 - last_caret_update < 1000;

        if (blink or newly_updated) {
            var buffer: [2]triangles.DrawInstance = undefined;
            const width = 3.0 * shared.render_scale;
            lines.getDrawVertexData(&buffer, position, Point{
                .x = position.x,
                .y = position.y + height,
            }, width, .{ 255, 255, 255, 255 }, width / 2);
            try triangles_buffer.appendSlice(&buffer);
        }
    }

    pub fn getCaretIndex(self: Text, id: [4]u32, relative_x: f32) ?u32 {
        var caret_index = id[1];
        if (caret_index > 0) {
            const char_details = self.text_vertex.items[caret_index - 1];

            // calculate if the click happened more on left side of the char, in this case put caret before the char, not after
            const left_side = @abs(relative_x - char_details.relative_bounds[0].x) < @abs(relative_x - char_details.relative_bounds[2].x);
            if (left_side) {
                caret_index -= 1;
            }

            return caret_index;
        }

        return null;
    }

    pub fn serialize(self: Text) Serialized {
        return Serialized{
            .id = self.id,
            .content = self.content,
            .font_size = self.font_size,
            .bounds = self.bounds,
        };
    }
};

pub const Serialized = struct {
    id: u32,
    content: ?[]const u8, // it's a null poitner exception if content is empty, that's wy we allow null
    // to avoid throwing the exception
    bounds: [4]PointUV,
    font_size: f32,
};
