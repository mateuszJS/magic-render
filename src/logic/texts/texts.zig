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

const ENTER_CHAR_CODE = 10;
const BOUNDS_MIX_WIDTH = 0.3; // will be multiplied by font_size

pub var caret_position: u32 = 0;
pub var selection_end_position: u32 = 0; // selection start is indicated by caret_position
pub var last_caret_update: u32 = 0;

pub const CharVertex = struct {
    bounds: [6]PointUV,
    sdf_texture_id: ?u32,
    origin: Point, // origin of the char (bottom left corner), useful for drawing selection/caret/picking
};

pub const Text = struct {
    id: u32,
    start: Point,
    content: []const u8,
    max_width: f32,
    font_size: f32,
    bounds: [4]PointUV,
    line_height: f32 = 1.2, // line height multiplier
    text_vertex: std.ArrayList(CharVertex),

    pub fn new(
        id: u32,
        content: []const u8,
        bounds: ?[4]PointUV,
        start: Point,
        max_width: f32,
        font_size: f32,
    ) !Text {
        var text = Text{
            .id = id,
            .start = start,
            .content = content,
            .max_width = max_width,
            .font_size = font_size,
            .bounds = bounds orelse consts.DEFAULT_BOUNDS,
            .text_vertex = std.ArrayList(CharVertex).init(std.heap.page_allocator),
        };

        try text.computeText();

        return text;
    }

    fn getDrawBounds(self: Text, x: f32, y: f32, width: f32, height: f32, origin: Point) [6]PointUV {
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

    pub fn computeText(self: *Text) !void {
        var updated_content = std.ArrayList(u8).init(std.heap.page_allocator);

        self.text_vertex.clearAndFree();
        self.text_vertex.deinit();
        self.text_vertex = std.ArrayList(CharVertex).init(std.heap.page_allocator);

        const lh = self.font_size * self.line_height;
        var longest_line: f32 = 0.0;
        var next_pos = Point{ // start of the very first char(bottom left corner of the char)
            .x = self.start.x,
            .y = self.start.y - lh,
        };

        for (self.content, 0..) |c, i| {
            const char_width = if (c == ENTER_CHAR_CODE) b: {
                next_pos = Point{
                    .x = self.start.x,
                    .y = next_pos.y - lh,
                };
                break :b 0.0;
            } else b: {
                const char_details = try fonts.get(0, c);
                break :b (char_details.x + char_details.width) * self.font_size;
            };
            var space_before = try self.getBeforeKerning(i) * self.font_size;

            const exceeded_max_width = (next_pos.x + space_before + char_width) - self.start.x > self.max_width;
            if (exceeded_max_width) {
                try updated_content.appendSlice("\u{2060}");
                try self.text_vertex.append(CharVertex{
                    .bounds = self.getDrawBounds(0, 0, 0, 0, next_pos),
                    .sdf_texture_id = null,
                    .origin = next_pos,
                });

                // add word joiner character before line break so that when user copies the text, they get the same line breaks
                try updated_content.append(ENTER_CHAR_CODE);
                try self.text_vertex.append(CharVertex{
                    .bounds = self.getDrawBounds(0, 0, 0.1, 0, next_pos),
                    .sdf_texture_id = null,
                    .origin = next_pos,
                });

                next_pos = Point{
                    .x = self.start.x,
                    .y = next_pos.y - lh,
                };
                space_before = 0.0; // we start with a new line, so no kerning needed
            }

            const cd = try fonts.get(0, c); // char details

            const bounds = self.getDrawBounds(cd.x, cd.y, cd.width, cd.height, .{
                .x = next_pos.x + space_before,
                .y = next_pos.y,
            });
            try self.text_vertex.append(CharVertex{
                .bounds = bounds,
                .sdf_texture_id = cd.sdf_texture_id,
                .origin = next_pos,
            });

            next_pos.x += space_before + char_width;
            longest_line = @max(longest_line, next_pos.x - self.start.x);

            try updated_content.append(c);
        }

        longest_line = @max(longest_line, self.font_size * BOUNDS_MIX_WIDTH);
        self.bounds = [_]PointUV{
            .{ .x = self.start.x, .y = self.start.y, .u = 0.0, .v = 1.0 },
            .{ .x = self.start.x + longest_line, .y = self.start.y, .u = 1.0, .v = 1.0 },
            .{ .x = self.start.x + longest_line, .y = next_pos.y, .u = 1.0, .v = 0.0 },
            .{ .x = self.start.x, .y = next_pos.y, .u = 0.0, .v = 0.0 },
        };
        self.content = try updated_content.toOwnedSlice();
    }

    // returns kerning between the current and the previous char
    fn getBeforeKerning(self: Text, start_index: usize) !f32 {
        const kerning =
            if (start_index > 0)
                try fonts.get_kerning(0, self.content[start_index - 1], self.content[start_index])
            else
                0.0;

        return kerning;
    }

    pub fn addTextSelectionDrawVertex(
        triangles_buffer: *std.ArrayList(triangles.DrawInstance),
        start: Point,
        width: f32,
        height: f32,
    ) !void {
        var buffer: [2]triangles.DrawInstance = undefined;
        rects.getDrawVertexData(
            &buffer,
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
        position: PointUV,
        height: f32,
        time_u32: u32,
    ) !void {
        const blink = (time_u32 / 700) % 2 == 0;
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

    pub fn getCaretIndex(self: Text, id: [4]u32, x: f32) ?u32 {
        var caret_index = id[1];
        if (caret_index > 0) {
            const char_details = self.text_vertex.items[caret_index - 1];

            // calculate if the click happened more on left side of the char, in this case put caret before the char, not after
            const left_side = @abs(x - char_details.bounds[0].x) < @abs(x - char_details.bounds[2].x);
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
            .start = self.start,
            .content = self.content,
            .max_width = self.max_width,
            .font_size = self.font_size,
            .bounds = self.bounds,
        };
    }
};

pub const Serialized = struct {
    id: u32,
    start: Point,
    content: []const u8,
    max_width: f32,
    font_size: f32,
    bounds: [4]PointUV,
};
