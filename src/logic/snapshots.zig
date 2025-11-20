// This module is responsible to generate snapshots

const utils = @import("utils.zig");
const AssetSerialized = @import("types.zig").AssetSerialized;
const State = @import("types.zig").State;
const shared = @import("shared.zig");
const types = @import("types.zig");
const std = @import("std");
const asset_props = @import("asset_props.zig");

pub const ProjectSnapshot = struct {
    width: f32,
    height: f32,
    assets: []const AssetSerialized,
};

pub var passSnapshot: *const fn (ProjectSnapshot, bool) void = undefined;
pub var skip_snapshot: bool = false;

const THROTTLING_TICKS = 5;

var first_call_tick: ?u32 = null;
var with_snapshot = false;
var commit = false;

pub fn triggerNewSnapshot(with_snapshot_param: bool, commit_param: bool) void {
    if (skip_snapshot) {
        return;
    }

    if (with_snapshot == false) {
        with_snapshot = with_snapshot_param;
    }

    if (commit == false) {
        commit = commit_param;
    }

    if (first_call_tick == null) {
        first_call_tick = shared.ticks;
    }
}

pub fn loop(state: State) !void {
    if (first_call_tick) |tick| {
        if (shared.ticks - tick > THROTTLING_TICKS) {
            try generateNewSnapshot(state);
            first_call_tick = null;
            with_snapshot = false;
            commit = false;
        }
    }
}

fn getCurrSnapshot(state: State) !ProjectSnapshot {
    var new_assets_update = std.ArrayList(AssetSerialized).init(std.heap.page_allocator);
    var iterator = state.assets.iterator();
    while (iterator.next()) |asset_entry| {
        switch (asset_entry.value_ptr.*) {
            .img => |img| {
                try new_assets_update.append(AssetSerialized{
                    .img = img.serialize(),
                });
            },
            .shape => |shape| {
                try new_assets_update.append(AssetSerialized{
                    .shape = try shape.serialize(std.heap.page_allocator),
                });
            },
            .text => |text| {
                try new_assets_update.append(AssetSerialized{
                    .text = try text.serialize(std.heap.page_allocator),
                });
            },
        }
    }

    const curr_project_snapshot: ProjectSnapshot = .{
        .width = state.width,
        .height = state.height,
        .assets = try new_assets_update.toOwnedSlice(),
    };

    return curr_project_snapshot;
}

var last_project_snapshot = ProjectSnapshot{
    .width = 0,
    .height = 0,
    .assets = &.{},
};

// @param with_snapshot: while moving in history, we don't want to produce snapshots.
// Otherwise we won't recognize what snapshot comes from undo/redo and what are actual changes which causes history cut

// @param commit: whether the changes are permament(true) or it's just preview of changes(false)
fn generateNewSnapshot(state: State) !void {
    if (with_snapshot == false and commit == false) {
        @panic("generateNewSnapshot called with with_snapshot == false and commit == false, so this function has NO effect");
    }
    // we might consider different params/data structure, to be more precise about only 3 scenarios available
    // 1. history update -> compare & save in zig, do not produce snapshot
    // 2. preview of changes -> do not compare & save in zig but DO produce snapshot
    // 3. normal/common changes -> with comparing & saving & generating a snapshot

    const curr_snapshot = try getCurrSnapshot(state);

    if (commit) {
        // if it's not a commit, then we do not care about limiting snapshots
        const is_project_size_same = utils.equalF32(last_project_snapshot.width, state.width) and utils.equalF32(last_project_snapshot.height, state.height);
        if (is_project_size_same and curr_snapshot.assets.len == last_project_snapshot.assets.len) {
            var all_match = true;

            for (curr_snapshot.assets, last_project_snapshot.assets) |new_asset, old_asset| {
                switch (old_asset) {
                    .img => |old_img| {
                        if (!old_img.compare(new_asset.img)) {
                            all_match = false;
                            break;
                        }
                    },
                    .shape => |old_shape| {
                        if (!old_shape.compare(new_asset.shape)) {
                            all_match = false;
                            break;
                        }
                    },
                    .text => |old_text| {
                        if (!old_text.compare(new_asset.text)) {
                            all_match = false;
                            break;
                        }
                    },
                }
            }

            if (all_match) {
                std.heap.page_allocator.free(curr_snapshot.assets);
                return;
            }
        }

        std.heap.page_allocator.free(last_project_snapshot.assets);
        last_project_snapshot = curr_snapshot;
    }

    if (with_snapshot) {
        passSnapshot(curr_snapshot, commit);
    }

    if (last_project_snapshot.assets.ptr != curr_snapshot.assets.ptr) {
        std.heap.page_allocator.free(curr_snapshot.assets);
    }
}

pub fn deinit() void {
    std.heap.page_allocator.free(last_project_snapshot.assets);
    last_project_snapshot = .{
        .width = 0,
        .height = 0,
        .assets = &.{},
    };
    passSnapshot = undefined;
}
