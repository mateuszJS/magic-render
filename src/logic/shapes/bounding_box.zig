const Point = @import("../types.zig").Point;
const std = @import("std");

/// Represents a 2D bounding box with minimum and maximum coordinates
pub const BoundingBox = struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
};

/// Calculate real bounding box for a cubic Bézier curve by finding extrema
/// This function finds the mathematically precise bounding box by:
/// 1. Including the curve endpoints (t=0 and t=1)
/// 2. Finding extrema points where the derivative equals zero
/// 3. Evaluating the curve at those extrema to get the true bounds
pub fn calculateCubicBezierRealBounds(p0: Point, p1: Point, p2: Point, p3: Point) BoundingBox {
    // Start with endpoints (t=0 and t=1)
    var min_x = @min(p0.x, p3.x);
    var max_x = @max(p0.x, p3.x);
    var min_y = @min(p0.y, p3.y);
    var max_y = @max(p0.y, p3.y);

    // For cubic Bézier: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
    // Derivative: B'(t) = 3(1-t)²(P1-P0) + 6(1-t)t(P2-P1) + 3t²(P3-P2)
    // Setting B'(t) = 0 gives us extrema

    // X component extrema
    const a_x = 3.0 * (p3.x - 3.0 * p2.x + 3.0 * p1.x - p0.x);
    const b_x = 6.0 * (p2.x - 2.0 * p1.x + p0.x);
    const c_x = 3.0 * (p1.x - p0.x);

    var extrema_x_buffer: [2]f32 = undefined;
    const extrema_x = solveQuadratic(a_x, b_x, c_x, &extrema_x_buffer);

    for (extrema_x) |t| {
        if (t > 0.0 and t < 1.0) {
            const x = evaluateCubicBezierComponent(t, p0.x, p1.x, p2.x, p3.x);
            min_x = @min(min_x, x);
            max_x = @max(max_x, x);
        }
    }

    // Y component extrema
    const a_y = 3.0 * (p3.y - 3.0 * p2.y + 3.0 * p1.y - p0.y);
    const b_y = 6.0 * (p2.y - 2.0 * p1.y + p0.y);
    const c_y = 3.0 * (p1.y - p0.y);

    var extrema_y_buffer: [2]f32 = undefined;
    const extrema_y = solveQuadratic(a_y, b_y, c_y, &extrema_y_buffer);

    for (extrema_y) |t| {
        if (t > 0.0 and t < 1.0) {
            const y = evaluateCubicBezierComponent(t, p0.y, p1.y, p2.y, p3.y);
            min_y = @min(min_y, y);
            max_y = @max(max_y, y);
        }
    }

    return BoundingBox{
        .min_x = min_x,
        .min_y = min_y,
        .max_x = max_x,
        .max_y = max_y,
    };
}

/// Solve quadratic equation ax² + bx + c = 0
/// Returns a slice of the provided buffer containing the solutions
/// The returned slice will have 0, 1, or 2 elements depending on the number of real solutions
fn solveQuadratic(a: f32, b: f32, c: f32, buffer: *[2]f32) []f32 {
    const epsilon = 1e-10;

    if (@abs(a) < epsilon) {
        // Linear equation: bx + c = 0
        if (@abs(b) < epsilon) {
            return buffer[0..0]; // No solutions
        }
        buffer[0] = -c / b;
        return buffer[0..1]; // One solution
    }

    const discriminant = b * b - 4.0 * a * c;
    if (discriminant < 0.0) {
        return buffer[0..0]; // No real solutions
    }

    if (@abs(discriminant) < epsilon) {
        buffer[0] = -b / (2.0 * a);
        return buffer[0..1]; // One solution (repeated root)
    }

    const sqrt_d = @sqrt(discriminant);
    buffer[0] = (-b + sqrt_d) / (2.0 * a);
    buffer[1] = (-b - sqrt_d) / (2.0 * a);
    return buffer[0..2]; // Two solutions
}

/// Evaluate cubic Bézier curve at parameter t for a single component (x or y)
/// Uses the standard cubic Bézier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
fn evaluateCubicBezierComponent(t: f32, p0: f32, p1: f32, p2: f32, p3: f32) f32 {
    const t2 = t * t;
    const t3 = t2 * t;
    const one_minus_t = 1.0 - t;
    const one_minus_t2 = one_minus_t * one_minus_t;
    const one_minus_t3 = one_minus_t2 * one_minus_t;

    return p0 * one_minus_t3 + 3.0 * p1 * t * one_minus_t2 + 3.0 * p2 * t2 * one_minus_t + p3 * t3;
}

/// Get bounding box from curves array with padding
/// Assumes curves array contains groups of 4 points (p0, p1, p2, p3) for each cubic Bézier
/// Returns an allocated slice of 6 points representing two triangles for the bounding rectangle
/// Caller owns the returned memory and must free it
pub fn getBoundingBox(curves: []const Point, padding: f32) BoundingBox {
    var box = BoundingBox{
        .min_x = std.math.inf(f32),
        .min_y = std.math.inf(f32),
        .max_x = -std.math.inf(f32),
        .max_y = -std.math.inf(f32),
    };

    const num_cubic_curves = curves.len / 4;

    var i: usize = 0;
    while (i < num_cubic_curves) : (i += 1) {
        const p0 = curves[i * 4 + 0];
        const p1 = curves[i * 4 + 1];
        const p2 = curves[i * 4 + 2];
        const p3 = curves[i * 4 + 3];

        // Calculate real bounding box for this cubic Bézier curve
        const bounds = calculateCubicBezierRealBounds(p0, p1, p2, p3);

        box.min_x = @min(box.min_x, bounds.min_x);
        box.min_y = @min(box.min_y, bounds.min_y);
        box.max_x = @max(box.max_x, bounds.max_x);
        box.max_y = @max(box.max_y, bounds.max_y);
    }

    box.min_x -= padding;
    box.min_y -= padding;
    box.max_x += padding;
    box.max_y += padding;

    return box;
}

// Test function
test "cubic bezier bounding box calculation" {
    const testing = std.testing;

    // Test a simple cubic Bézier curve
    const p0 = Point{ .x = 0.0, .y = 0.0 };
    const p1 = Point{ .x = 1.0, .y = 2.0 };
    const p2 = Point{ .x = 3.0, .y = 2.0 };
    const p3 = Point{ .x = 4.0, .y = 0.0 };

    const bounds = calculateCubicBezierRealBounds(p0, p1, p2, p3);

    // The curve should be bounded by the endpoints at minimum
    try testing.expect(bounds.min_x <= 0.0);
    try testing.expect(bounds.max_x >= 4.0);
    try testing.expect(bounds.min_y <= 0.0);
}

test "quadratic solver" {
    const testing = std.testing;

    // Test x² - 5x + 6 = 0 (solutions: 2 and 3)
    var buffer: [2]f32 = undefined;
    const solutions = solveQuadratic(1.0, -5.0, 6.0, &buffer);

    try testing.expect(solutions.len == 2);
    // Solutions might be in any order
    const sorted = std.sort.asc(f32);
    std.sort.insertionSort(f32, solutions, {}, sorted);
    try testing.expectApproxEqAbs(@as(f32, 2.0), solutions[0], 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 3.0), solutions[1], 1e-6);
}
