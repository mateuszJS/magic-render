const std = @import("std");
const fill = @import("fill.zig");
const utils = @import("../utils.zig");

pub const Effect = struct {
    dist_start: f32,
    dist_end: f32,
    fill: fill.Fill,
};

pub const Serialized = struct {
    dist_start: f32,
    dist_end: f32,
    fill: fill.SerializedFill,
};

pub fn serialize(effects: std.ArrayList(Effect), allocator: std.mem.Allocator) ![]Serialized {
    var effects_list = std.ArrayList(Serialized).init(allocator);

    for (effects.items) |effect| {
        try effects_list.append(Serialized{
            .dist_start = effect.dist_start,
            .dist_end = effect.dist_end,
            .fill = try effect.fill.serialize(allocator),
        });
    }

    return try effects_list.toOwnedSlice();
}

pub fn deinit(effects: std.ArrayList(Effect)) void {
    for (effects.items) |*effect| {
        effect.fill.deinit();
    }
    effects.deinit();
}

pub fn compareSerialized(a: []const Serialized, b: []const Serialized) bool {
    if (a.len != b.len) return false;

    for (a, b) |effect_a, effect_b| {
        if (!utils.equalF32(effect_a.dist_start, effect_b.dist_start)) return false;
        if (!utils.equalF32(effect_a.dist_end, effect_b.dist_end)) return false;
        if (!effect_a.fill.compare(effect_b.fill)) return false;
    }

    return true;
}

pub fn deserialize(effects: []const Serialized, allocator: std.mem.Allocator) !std.ArrayList(Effect) {
    var effects_list = std.ArrayList(Effect).init(allocator);

    for (effects) |e| {
        try effects_list.append(Effect{
            .dist_start = e.dist_start,
            .dist_end = e.dist_end,
            .fill = try fill.Fill.new(e.fill, allocator),
        });
    }

    return effects_list;
}
