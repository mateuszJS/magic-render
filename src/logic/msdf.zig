const std = @import("std");

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

const TRIANGLE_DRAW_VERTICIES_COUNT = (4 + 2) * 3 + 4; // 4 -> x,y,z,w, 2 -> u,v, 3 verticies, 4 -> color
pub const DRAW_VERTICIES_COUNT = TRIANGLE_DRAW_VERTICIES_COUNT * 2;

var icons: std.AutoHashMap(IconId, IconData) = undefined;

pub fn init_icons(data: []const f32) void {
    icons = std.AutoHashMap(IconId, IconData).init(std.heap.page_allocator);

    var i: usize = 0;
    while (i < data.len) : (i += 7) {
        const icon_id: u32 = @intFromFloat(data[i]);
        std.debug.print("icon_id: {}\n", .{icon_id});
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

pub fn deinit_icons() void {
    icons.deinit();
}

pub fn get_msdf_vertex_data(icon_id: IconId, x: f32, y: f32, width: f32, color: [4]f32) [DRAW_VERTICIES_COUNT]f32 {
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

    return [_]f32{
        dest_x_left, dest_y_bottom, 0.0, 1.0, source_x_left, source_y_bottom, //
        dest_x_left, dest_y_top, 0.0, 1.0, source_x_left, source_y_top, //
        dest_x_right, dest_y_top, 0.0, 1.0, source_x_right, source_y_top, //
        color[0], color[1], color[2], color[3], //
        // second triangle
        dest_x_right, dest_y_top, 0.0, 1.0, source_x_right, source_y_top, //
        dest_x_right, dest_y_bottom, 0.0, 1.0, source_x_right, source_y_bottom, //
        dest_x_left, dest_y_bottom, 0.0, 1.0, source_x_left, source_y_bottom, //
        color[0], color[1], color[2], color[3], //
    };
}
