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

pub const SDF_RESIZE_STEP = 1.5;
// ususally when user zoom we need to gernerate tons of new SDF, jsut slightly bigger than preivous one
// generating sdf 1.5 tiems bigger reduces number of generations

pub const HIGHLIGHT_PATH_PROGRAM_ID: u32 = 1;
pub const SOLID_COLOR_PROGRAM_ID: u32 = 2;
pub const ERROR_PROGRAM_ID: u32 = 3;

pub const HIGHLIGHT_PATH_INPUTS_ID: u32 = 1;
pub const TRANSFORM_UI_INPUTS_ID: u32 = 2;
pub const TRANSFORM_UI_HOVER_INPUTS_ID: u32 = 3;
pub const DEFAULT_INPUTS_ID: u32 = 4;
pub const COMPILING_INPUTS_ID: u32 = 5;
pub const ERROR_INPUTS_ID: u32 = 6;

pub const SKELETON_LINE_WIDTH: f32 = 2.0;
