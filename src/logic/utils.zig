const math = @import("std").math;
const consts = @import("consts.zig");
const PointUV = @import("types.zig").PointUV;
const Matrix3x3 = @import("matrix.zig").Matrix3x3;

pub fn findMidAngle(angle1: f32, angle2: f32) f32 {
    const x = math.cos(angle1) + math.cos(angle2);
    const y = math.sin(angle1) + math.sin(angle2);
    return math.atan2(y, x);
}

pub fn angleDifference(angle1: f32, angle2: f32) f32 {
    const delta = angle2 - angle1;
    return math.atan2(math.sin(delta), math.cos(delta)) + math.pi;
}

pub fn getNextPowerOfTwo(value: f32) f32 {
    return @exp2(@ceil(@log2(value)));
}

pub fn equalF32(a: f32, b: f32) bool {
    return @abs(a - b) <= consts.EPSILON;
}

// 0.001 tolerance for bounds comparison
// most of precision issues start at transform_ui module, where we perform lots of trigonometric operations
pub fn equalBoundPoint(a: anytype, b: anytype) bool {
    return @abs(a.x - b.x) < 0.001 and @abs(a.y - b.y) < 0.001;
}

pub fn compareBounds(bounds1: [4]PointUV, bounds2: [4]PointUV) bool {
    for (bounds1, 0..) |b1, i| {
        const b2 = bounds2[i];
        if (!equalBoundPoint(b1, b2)) {
            return false;
        }
    }
    return true;
}

pub fn createBounds(w: f32, h: f32) [4]PointUV {
    return [_]PointUV{
        .{ .x = 0, .y = h, .u = 0, .v = 1 },
        .{ .x = w, .y = h, .u = 1, .v = 1 },
        .{ .x = w, .y = 0, .u = 1, .v = 0 },
        .{ .x = 0, .y = 0, .u = 0, .v = 0 },
    };
}

pub fn transformBoundsUV(self: [4]PointUV, matrix: Matrix3x3) [6]PointUV {
    const b = self.relative_bounds;
    return [_]PointUV{
        // first triangle
        matrix.getUV(.{ .x = b[3].x, .y = b[3].y, .u = 0.0, .v = 0.0 }),
        matrix.getUV(.{ .x = b[0].x, .y = b[0].y, .u = 0.0, .v = 1.0 }),
        matrix.getUV(.{ .x = b[1].x, .y = b[1].y, .u = 1.0, .v = 1.0 }),
        // second triangle
        matrix.getUV(.{ .x = b[1].x, .y = b[1].y, .u = 1.0, .v = 1.0 }),
        matrix.getUV(.{ .x = b[2].x, .y = b[2].y, .u = 1.0, .v = 0.0 }),
        matrix.getUV(.{ .x = b[3].x, .y = b[3].y, .u = 0.0, .v = 0.0 }),
    };
}

pub fn getNextStep(base: f32, input: f32) f32 {
    // Rule 1: Minimum is 50
    if (input <= base) return base;

    // We want the next step strictly greater than the input.
    // We normalize by dividing by 50.
    const normalized = input / base;

    // math.log2 for floats returns the exponent.
    // Example: if normalized is 2.0, log2 is 1.0.
    // We use floor + 1 to get the next power of 2 exponent.
    const exponent = math.floor(math.log2(normalized)) + 1.0;

    // Calculate 2^exponent
    const next_p2 = math.pow(f32, 2.0, exponent);

    // Return as integer
    return base * next_p2;
}
