const shared = @import("../shared.zig");
const texts = @import("./texts.zig");
const Point = @import("../types.zig").Point;
const triangles = @import("../triangles.zig");
const lines = @import("../lines.zig");
const Matrix3x3 = @import("../matrix.zig").Matrix3x3;

pub var position: u32 = 0;
pub var last_update: u32 = 0;
pub var selection_end_position: u32 = 0;
// selection start is indicated by caret.position

pub fn isCaretShown() bool {
    const CARET_BLINK_INTERVAL_MS = 700;
    const blink = (shared.time_u32 / CARET_BLINK_INTERVAL_MS) % 2 == 0;
    const newly_updated = shared.time_u32 - last_update < 1000;
    return blink or newly_updated;
}

pub fn addDrawVertex(
    text: *texts.Text,
    relative_start: Point,
) ?[2]triangles.DrawInstance {
    const matrix = Matrix3x3.getMatrixFromRectangleNoScale(text.bounds);
    const relative_end = Point{
        .x = relative_start.x,
        .y = relative_start.y + text.typo_props.font_size * text.typo_props.line_height,
    };

    var buffer: [2]triangles.DrawInstance = undefined;
    const width = 3.0 * shared.ui_scale;
    lines.getDrawVertexData(
        &buffer,
        matrix.get(relative_start),
        matrix.get(relative_end),
        width,
        .{ 255, 255, 255, 255 },
        width / 2,
    );
    return buffer;
}
