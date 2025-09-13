const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const consts = @import("../consts.zig");
const std = @import("std");
const fonts = @import("fonts.zig");
const chars = @import("chars.zig");

pub var caret_position: u32 = 0;
pub var selection_end_position: u32 = 0; // selection start is indicated by caret_position
pub var last_caret_update: u32 = 0;

pub const Text = struct {
    id: u32,
    start: Point,
    content: []const u8,
    max_width: f32,
    font_size: f32,
    bounds: [4]PointUV,
    line_height: f32 = 1.2, // line height multiplier

    pub fn new(
        id: u32,
        content: []const u8,
        bounds: ?[4]PointUV,
        start: Point,
        max_width: f32,
        font_size: f32,
    ) Text {
        return Text{
            .id = id,
            .start = start,
            .content = content,
            .max_width = max_width,
            .font_size = font_size,
            .bounds = bounds orelse consts.DEFAULT_BOUNDS,
        };
    }

    pub fn updateContent(self: *Text, new_content: []const u8) void {
        std.debug.print("Updating text content from '{s}' to '{s}'\n", .{ self.content, new_content });
        self.content = new_content;
    }

    pub fn getDrawBounds(self: Text, char: chars.Details, position: Point) [6]PointUV {
        const w = char.width * self.font_size;
        const h = char.height * self.font_size;
        const p = Point{
            .x = position.x + char.x * self.font_size,
            .y = position.y + char.y * self.font_size,
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
