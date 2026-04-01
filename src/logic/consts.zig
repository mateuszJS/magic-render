const std = @import("std");
const PointUV = @import("types.zig").PointUV;
const Point = @import("types.zig").Point;

pub const DEFAULT_BOUNDS = [4]PointUV{
    .{ .x = 0.0, .y = 1.0, .u = 0.0, .v = 1.0 },
    .{ .x = 1.0, .y = 1.0, .u = 1.0, .v = 1.0 },
    .{ .x = 1.0, .y = 0.0, .u = 1.0, .v = 0.0 },
    .{ .x = 0.0, .y = 0.0, .u = 0.0, .v = 0.0 },
};

pub const POINT_ZERO = Point{ .x = 0.0, .y = 0.0 };

pub const MIN_TEXTURE_SIZE: f32 = 1;

pub const EPSILON = std.math.floatEps(f32);

pub const SDF_SAFE_PADDING = 1; // safe padding to avoid harsh edges + avoid bleeding errors

pub const ASSET_ID_MIN: u32 = 1000;

pub const INFINITE_DISTANCE = std.math.floatMax(f32); // purely for SDF effects
