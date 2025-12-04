const Point = @import("../types.zig").Point;
const std = @import("std");
const utils = @import("../utils.zig");

pub const GradientStop = extern struct {
    color: [4]f32,
    offset: f32, // 0..1

    pub fn compare(self: GradientStop, other: GradientStop) bool {
        if (!utils.equalF32(self.offset, other.offset)) return false;

        for (self.color, other.color) |color_a, color_b| {
            if (!utils.equalF32(color_a, color_b)) return false;
        }

        return true;
    }
};

const SerializedLinearGradient = struct {
    start: Point,
    end: Point,
    stops: []GradientStop,
};

const SerializedRadialGradient = struct {
    radius_ratio: f32,
    start: Point,
    end: Point,
    stops: []GradientStop,
};

pub const SerializedFill = union(enum) {
    linear: SerializedLinearGradient,
    radial: SerializedRadialGradient,
    solid: [4]f32,
    program_id: u32,

    pub fn compare(self: SerializedFill, other: SerializedFill) bool {
        return switch (self) {
            .solid => |color| switch (other) {
                .solid => |other_color| {
                    for (color, other_color) |component_a, component_b| {
                        if (!utils.equalF32(component_a, component_b)) return false;
                    }
                    return true;
                },
                else => false,
            },
            .linear => |g| switch (other) {
                .linear => |other_g| {
                    if (!utils.equalBoundPoint(g.start, other_g.start) or
                        !utils.equalBoundPoint(g.end, other_g.end))
                    {
                        return false;
                    }

                    if (g.stops.len != other_g.stops.len) return false;
                    for (g.stops, other_g.stops) |stop_a, stop_b| {
                        if (!stop_a.compare(stop_b)) return false;
                    }

                    return true;
                },
                else => false,
            },
            .radial => |g| switch (other) {
                .radial => |other_g| {
                    if (!utils.equalF32(g.radius_ratio, other_g.radius_ratio) or
                        !utils.equalBoundPoint(g.start, other_g.start) or
                        !utils.equalBoundPoint(g.end, other_g.end))
                    {
                        return false;
                    }

                    if (g.stops.len != other_g.stops.len) return false;

                    for (g.stops, 0..) |stop, i| {
                        if (!stop.compare(other_g.stops[i])) return false;
                    }

                    return true;
                },
                else => false,
            },
            .program_id => |id| switch (other) {
                .program_id => |other_id| return id == other_id,
                else => false,
            },
        };
    }
};

pub const LinearGradient = struct {
    start: Point,
    end: Point,
    stops: std.ArrayList(GradientStop),
};

pub const RadialGradient = struct {
    radius_ratio: f32,
    start: Point,
    end: Point,
    stops: std.ArrayList(GradientStop),
};

pub const Fill = union(enum) {
    linear: LinearGradient,
    radial: RadialGradient,
    solid: [4]f32,
    program_id: u32,

    pub fn new(input: SerializedFill, allocator: std.mem.Allocator) !Fill {
        return switch (input) {
            .solid => |color| {
                return Fill{
                    .solid = color,
                };
            },
            .linear => |gradient| {
                var stops = std.ArrayList(GradientStop).init(allocator);
                try stops.appendSlice(gradient.stops);

                if (stops.items.len > 10) {
                    @panic("Max stops number is 10!");
                }

                return Fill{
                    .linear = .{
                        .start = gradient.start,
                        .end = gradient.end,
                        .stops = stops,
                    },
                };
            },
            .radial => |gradient| {
                var stops = std.ArrayList(GradientStop).init(allocator);
                try stops.appendSlice(gradient.stops);

                if (stops.items.len > 10) {
                    @panic("Max stops number is 10!");
                }

                return Fill{
                    .radial = .{
                        .start = gradient.start,
                        .end = gradient.end,
                        .radius_ratio = gradient.radius_ratio,
                        .stops = stops,
                    },
                };
            },
            .program_id => |id| {
                return Fill{
                    .program_id = id,
                };
            },
        };
    }

    pub fn serialize(self: Fill, allocator: std.mem.Allocator) !SerializedFill {
        return switch (self) {
            .solid => |color| {
                return SerializedFill{
                    .solid = color,
                };
            },
            .linear => |g| {
                return SerializedFill{
                    .linear = .{
                        .start = g.start,
                        .end = g.end,
                        .stops = try allocator.dupe(GradientStop, g.stops.items),
                    },
                };
            },
            .radial => |g| {
                return SerializedFill{
                    .radial = .{
                        .start = g.start,
                        .end = g.end,
                        .radius_ratio = g.radius_ratio,
                        .stops = g.stops.items,
                    },
                };
            },
            .program_id => |id| {
                return SerializedFill{
                    .program_id = id,
                };
            },
        };
    }

    pub fn deinit(self: *Fill) void {
        switch (self.*) {
            .solid => {},
            .linear => |*g| g.stops.deinit(),
            .radial => |*g| g.stops.deinit(),
            .program_id => {},
        }
    }
};
