const std = @import("std");
const sdf = @import("sdf/sdf.zig");
const fill = @import("sdf/fill.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

pub const SerializedSdfEffect = struct {
    dist_start: f32,
    dist_end: f32,
    fill: fill.SerializedFill,
};

pub const Filter = struct {
    gaussianBlur: types.Point,
};

pub const Props = struct {
    sdf_effects: std.ArrayList(sdf.Effect),
    filter: ?Filter,
    opacity: f32,

    pub fn serialize(self: Props, allocator: std.mem.Allocator) !SerializedProps {
        var effects_list = std.ArrayList(SerializedSdfEffect).init(allocator);
        for (self.sdf_effects.items) |effect| {
            try effects_list.append(SerializedSdfEffect{
                .dist_start = effect.dist_start,
                .dist_end = effect.dist_end,
                .fill = try effect.fill.serialize(allocator),
            });
        }

        return SerializedProps{
            .sdf_effects = try effects_list.toOwnedSlice(),
            .filter = self.filter,
            .opacity = self.opacity,
        };
    }

    pub fn deinit(self: *Props) void {
        for (self.sdf_effects.items) |*effect| {
            effect.fill.deinit();
        }
        self.sdf_effects.deinit();
    }
};

pub const SerializedProps = struct {
    sdf_effects: []const SerializedSdfEffect = &.{},
    filter: ?Filter = null,
    opacity: f32 = 1.0,

    pub fn compare(self: SerializedProps, other: SerializedProps) bool {
        if (!utils.equalF32(self.opacity, other.opacity)) return false;

        if (self.filter) |filter| {
            if (other.filter) |other_filter| {
                if (!utils.equalBoundPoint(filter.gaussianBlur, other_filter.gaussianBlur)) {
                    return false;
                }
            } else {
                return false;
            }
        } else if (other.filter != null) {
            return false;
        }

        if (self.sdf_effects.len != other.sdf_effects.len) return false;

        for (self.sdf_effects, other.sdf_effects) |effect_a, effect_b| {
            if (!utils.equalF32(effect_a.dist_start, effect_b.dist_start)) return false;
            if (!utils.equalF32(effect_a.dist_end, effect_b.dist_end)) return false;
            if (!effect_a.fill.compare(effect_b.fill)) return false;
        }

        return true;
    }
};

// This function cannot be part of SerializedProps struct because it returns []GradientStop(part of props.fill)
// and there is no writer interface created(only []u8 can be returned as a slices)
pub fn deserializeProps(self: SerializedProps, allocator: std.mem.Allocator) !Props {
    var effects_list = std.ArrayList(sdf.Effect).init(allocator);
    for (self.sdf_effects) |effect| {
        try effects_list.append(sdf.Effect{
            .dist_start = effect.dist_start,
            .dist_end = effect.dist_end,
            .fill = try fill.Fill.new(effect.fill, allocator),
        });
    }

    return Props{
        .sdf_effects = effects_list,
        .filter = self.filter,
        .opacity = self.opacity,
    };
}
