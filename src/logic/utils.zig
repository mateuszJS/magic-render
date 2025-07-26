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

pub fn get_next_power_of_two(value: f32) f32 {
    return @exp2(@ceil(@log2(value)));
}

pub fn compare_floats(a: f32, b: f32) bool {
    return @abs(a - b) < math.floatEps(f32);
}
