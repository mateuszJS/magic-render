const std = @import("std");
const PointUV = @import("types.zig").PointUV;

pub const IconId = enum(u32) {
    rotate = 57345, // U+E001
    trash = 57346, // U+E002
};

pub const IconData = struct {
    id: IconId,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    real_width: f32,
    real_height: f32,
};

const DEFAULT_ICON = IconData{
    .id = IconId.rotate,
    .x = 0.0,
    .y = 0.0,
    .width = 0.0,
    .height = 0.0,
    .real_width = 0.0,
    .real_height = 0.0,
}; // used when an icon is not found(not loaded yet)

var icons: std.AutoHashMap(IconId, IconData) = undefined;

pub fn initIcons(data: []const f32) void {
    icons = std.AutoHashMap(IconId, IconData).init(std.heap.page_allocator);

    var i: usize = 0;
    while (i < data.len) : (i += 7) {
        const icon_id: u32 = @intFromFloat(data[i]);

        const icon = IconData{
            .id = std.meta.intToEnum(IconId, icon_id) catch unreachable,
            .x = data[i + 1],
            .y = data[i + 2],
            .width = data[i + 3],
            .height = data[i + 4],
            .real_width = data[i + 5],
            .real_height = data[i + 6],
        };
        icons.put(icon.id, icon) catch unreachable;
    }
}

pub fn deinitIcons() void {
    icons.clearAndFree();
}

pub const DrawInstance = extern struct {
    points: [3]PointUV,
    color: [4]u8,
};

pub fn getDrawVertexData(icon_id: IconId, x: f32, y: f32, width: f32, color: [4]u8) [2]DrawInstance {
    const icon = icons.get(icon_id) orelse DEFAULT_ICON;

    const scale = width / icon.real_width;
    const dest_y_top = y + icon.real_height * scale;
    const dest_y_bottom = y;
    const dest_x_left = x;
    const dest_x_right = x + icon.real_width * scale;

    const source_y_top = 1.0 - icon.y;
    const source_y_bottom = 1.0 - (icon.y + icon.height);
    const source_x_left = icon.x;
    const source_x_right = icon.x + icon.width;

    return [_]DrawInstance{
        .{
            .points = [_]PointUV{
                .{ .x = dest_x_left, .y = dest_y_bottom, .u = source_x_left, .v = source_y_bottom },
                .{ .x = dest_x_left, .y = dest_y_top, .u = source_x_left, .v = source_y_top },
                .{ .x = dest_x_right, .y = dest_y_top, .u = source_x_right, .v = source_y_top },
            },
            .color = color,
        },
        .{
            .points = [_]PointUV{
                .{ .x = dest_x_right, .y = dest_y_top, .u = source_x_right, .v = source_y_top },
                .{ .x = dest_x_right, .y = dest_y_bottom, .u = source_x_right, .v = source_y_bottom },
                .{ .x = dest_x_left, .y = dest_y_bottom, .u = source_x_left, .v = source_y_bottom },
            },
            .color = color,
        },
    };
}
