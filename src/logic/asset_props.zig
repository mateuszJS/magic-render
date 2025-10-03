const std = @import("std");
const sdf = @import("./sdf/sdf.zig");
const fill = @import("./sdf/fill.zig");
const types = @import("./types.zig");

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
};

pub const SerializedProps = struct {
    sdf_effects: []const SerializedSdfEffect = &.{},
    filter: ?Filter = null,
    opacity: f32 = 1.0,
};

pub fn serializeProps(allocator: std.mem.Allocator, props: Props) !SerializedProps {
    var effects_list = std.ArrayList(SerializedSdfEffect).init(allocator);
    for (props.sdf_effects.items) |effect| {
        try effects_list.append(SerializedSdfEffect{
            .dist_start = effect.dist_start,
            .dist_end = effect.dist_end,
            .fill = effect.fill.serialize(),
        });
    }

    return SerializedProps{
        .sdf_effects = try effects_list.toOwnedSlice(),
        .filter = props.filter,
        .opacity = props.opacity,
    };
}
