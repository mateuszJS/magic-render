const Point = @import("../types.zig").Point;
const PointUV = @import("../types.zig").PointUV;
const consts = @import("../consts.zig");
const std = @import("std");
const fonts = @import("fonts.zig");
const chars = @import("chars.zig");

pub const Text = struct {
    id: u32,
    start: Point,
    content: []const u8,
    max_width: f32,
    font_size: f32,
    bounds: [4]PointUV,

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
        _ = self; // autofix
        _ = char; // autofix
        const w = 100.0; //char.width * self.font_size;
        const h = 100.0; //char.height * self.font_size;
        return [_]PointUV{
            .{ .x = position.x, .y = position.y, .u = 0.0, .v = 0.0 },
            .{ .x = position.x, .y = position.y + h, .u = 0.0, .v = 1.0 },
            .{ .x = position.x + w, .y = position.y + h, .u = 1.0, .v = 1.0 },
            .{ .x = position.x + w, .y = position.y + h, .u = 1.0, .v = 1.0 },
            .{ .x = position.x + w, .y = position.y, .u = 1.0, .v = 0.0 },
            .{ .x = position.x, .y = position.y, .u = 0.0, .v = 0.0 },
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
