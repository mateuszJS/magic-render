const shared = @import("../shared.zig");

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
