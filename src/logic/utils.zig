const math = @import("std").math;

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

const EPSILON = math.floatEps(f32);
pub fn cmpF32(a: f32, b: f32) bool {
    return @abs(a - b) < EPSILON;
}
