const Point = @import("../types.zig").Point;
const std = @import("std");
const utils = @import("../utils.zig");

pub const GradientStop = extern struct {
    color: [4]f32,
    offset: f32, // 0..1

    pub fn compare(self: GradientStop, other: GradientStop) bool {
        if (!utils.equalF32(self.offset, other.offset)) return false;

        for (self.color, 0..) |c, i| {
            if (!utils.equalF32(c, other.color[i])) return false;
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
    center: Point,
    destination: Point,
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
                    for (color, 0..) |c, i| {
                        if (!utils.equalF32(c, other_color[i])) return false;
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

                    for (g.stops, 0..) |stop, i| {
                        if (!stop.compare(other_g.stops[i])) return false;
                    }

                    return true;
                },
                else => false,
            },
            .radial => |g| switch (other) {
                .radial => |other_g| {
                    if (!utils.equalF32(g.radius_ratio, other_g.radius_ratio) or
                        !utils.equalBoundPoint(g.center, other_g.center) or
                        !utils.equalBoundPoint(g.destination, other_g.destination))
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
    center: Point,
    destination: Point,
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
                        .center = gradient.center,
                        .destination = gradient.destination,
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

    pub fn serialize(self: Fill) SerializedFill {
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
                        .stops = g.stops.items,
                    },
                };
            },
            .radial => |g| {
                return SerializedFill{
                    .radial = .{
                        .center = g.center,
                        .destination = g.destination,
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
