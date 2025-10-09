const math = @import("std").math;
const consts = @import("./consts.zig");
const PointUV = @import("types.zig").PointUV;

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
    return @abs(a - b) < consts.EPSILON;
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
