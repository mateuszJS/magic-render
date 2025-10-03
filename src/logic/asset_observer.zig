// This module handles notifying outside world when the selected asset changes
// in order for for example update UI with new sizes or effects

const shared = @import("shared.zig");
const types = @import("types.zig");
const std = @import("std");
const asset_props = @import("asset_props.zig");

const THROTTLING_TIME_MS = 100;

// ID of the asset is not passed on purpose
// UI should be dumb, show result and collect changes only
// not searching asset in the current assets state
pub const NotifyWorldFn = *const fn (?[4]types.PointUV, ?asset_props.SerializedProps) void;
pub var notifyWorld: NotifyWorldFn = undefined;

var first_call_time: ?f32 = null;

pub fn triggerUpdate() void {
    if (first_call_time == null) {
        first_call_time = shared.time;
    }
}

fn notify(option_asset: ?types.Asset) !void {
    if (option_asset) |asset| {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        switch (asset) {
            .img => |img| notifyWorld(img.bounds, asset_props.SerializedProps{}),
            .shape => |shape| {
                const props = try asset_props.serializeProps(allocator, shape.props);
                notifyWorld(shape.bounds, props);
            },
            .text => |text| {
                const props = try asset_props.serializeProps(allocator, text.props);
                notifyWorld(text.bounds, props);
            },
        }
    } else {
        notifyWorld(null, null);
    }
}

pub fn loop(option_asset: ?types.Asset) !void {
    if (first_call_time) |time| {
        if (shared.time - time > THROTTLING_TIME_MS) {
            try notify(option_asset);
            first_call_time = null;
        }
    }
}
