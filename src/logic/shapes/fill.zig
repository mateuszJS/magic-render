const Point = @import("../types.zig").Point;
const std = @import("std");
const Path = @import("paths.zig").Path;

pub const GradientStop = extern struct {
    color: [4]f32,
    offset: f32, // 0..1
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
        };
    }

    pub fn serialize(self: Fill) SerializedFill {
        return switch (self) {
            .solid => |color| {
                return SerializedFill{
                    .solid = color,
                };
            },
            .linear => |gradient| {
                return SerializedFill{
                    .linear = .{
                        .start = gradient.start,
                        .end = gradient.end,
                        .stops = gradient.stops.items,
                    },
                };
            },
            .radial => |gradient| {
                return SerializedFill{
                    .radial = .{
                        .center = gradient.center,
                        .destination = gradient.destination,
                        .radius_ratio = gradient.radius_ratio,
                        .stops = gradient.stops.items,
                    },
                };
            },
        };
    }
};
