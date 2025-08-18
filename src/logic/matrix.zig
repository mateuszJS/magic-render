// Matrix3x3 implementation for 2D affine transforms
const std = @import("std");
const Point = @import("types.zig").Point;

pub const Matrix3x3 = struct {
    values: [9]f32,

    pub fn identity() Matrix3x3 {
        return Matrix3x3{
            .values = [_]f32{
                1.0, 0.0, 0.0,
                0.0, 1.0, 0.0,
                0.0, 0.0, 1.0,
            },
        };
    }

    pub fn scaling(sx: f32, sy: f32) Matrix3x3 {
        return Matrix3x3{
            .values = [_]f32{
                sx,  0.0, 0.0,
                0.0, sy,  0.0,
                0.0, 0.0, 1.0,
            },
        };
    }

    pub fn translation(tx: f32, ty: f32) Matrix3x3 {
        return Matrix3x3{
            .values = [_]f32{
                1.0, 0.0, tx,
                0.0, 1.0, ty,
                0.0, 0.0, 1.0,
            },
        };
    }

    pub fn rotation(angle_rad: f32) Matrix3x3 {
        const c = std.math.cos(angle_rad);
        const s = std.math.sin(angle_rad);
        return Matrix3x3{
            .values = [_]f32{
                c,   -s,  0.0,
                s,   c,   0.0,
                0.0, 0.0, 1.0,
            },
        };
    }

    pub fn scale(self: *Matrix3x3, sx: f32, sy: f32) void {
        self.* = Matrix3x3.multiply(self.*, Matrix3x3.scaling(sx, sy));
    }

    pub fn rotate(self: *Matrix3x3, angle_rad: f32) void {
        self.* = Matrix3x3.multiply(self.*, Matrix3x3.rotation(angle_rad));
    }

    pub fn translate(self: *Matrix3x3, tx: f32, ty: f32) void {
        self.* = Matrix3x3.multiply(self.*, Matrix3x3.translation(tx, ty));
    }

    pub fn transpose(self: *Matrix3x3) void {
        const m = self.values;
        self.values = [_]f32{
            m[0], m[3], m[6],
            m[1], m[4], m[7],
            m[2], m[5], m[8],
        };
    }

    pub fn inverse(self: Matrix3x3) Matrix3x3 {
        const m = self.values;
        const a = m[0];
        const b = m[1];
        const c = m[2];
        const d = m[3];
        const e = m[4];
        const f = m[5];
        const g = m[6];
        const h = m[7];
        const i = m[8];
        const A = e * i - f * h;
        const B = -(d * i - f * g);
        const C = d * h - e * g;
        const D = -(b * i - c * h);
        const E = a * i - c * g;
        const F = -(a * h - b * g);
        const G = b * f - c * e;
        const H = -(a * f - c * d);
        const I = a * e - b * d;
        const det = a * A + b * B + c * C;
        if (@abs(det) < 1e-6) return Matrix3x3.identity(); // Handle singular matrix case
        // for example when scale is set to zero, we are unable to "invert" it to know previous value
        const inv_det = 1.0 / det;
        return Matrix3x3{
            .values = [_]f32{
                A * inv_det, D * inv_det, G * inv_det,
                B * inv_det, E * inv_det, H * inv_det,
                C * inv_det, F * inv_det, I * inv_det,
            },
        };
    }

    pub fn multiply(a: Matrix3x3, b: Matrix3x3) Matrix3x3 {
        const m = a.values;
        const n = b.values;
        return Matrix3x3{
            .values = [_]f32{
                m[0] * n[0] + m[1] * n[3] + m[2] * n[6],
                m[0] * n[1] + m[1] * n[4] + m[2] * n[7],
                m[0] * n[2] + m[1] * n[5] + m[2] * n[8],
                m[3] * n[0] + m[4] * n[3] + m[5] * n[6],
                m[3] * n[1] + m[4] * n[4] + m[5] * n[7],
                m[3] * n[2] + m[4] * n[5] + m[5] * n[8],
                m[6] * n[0] + m[7] * n[3] + m[8] * n[6],
                m[6] * n[1] + m[7] * n[4] + m[8] * n[7],
                m[6] * n[2] + m[7] * n[5] + m[8] * n[8],
            },
        };
    }

    pub fn approxEq(a: Matrix3x3, b: Matrix3x3, eps: f32) bool {
        var i: usize = 0;
        while (i < 9) : (i += 1) {
            if (@abs(a.values[i] - b.values[i]) > eps) return false;
        }
        return true;
    }

    pub fn transformPoint(self: Matrix3x3, p: anytype) Point {
        // Applies the matrix to a 2D point (x, y) and returns the transformed point
        const m = self.values;
        const tx = m[0] * p.x + m[1] * p.y + m[2];
        const ty = m[3] * p.x + m[4] * p.y + m[5];
        // For affine matrices, w is always 1, but for completeness:
        // const tw = m[6] * x + m[7] * y + m[8];
        return Point{ .x = tx, .y = ty };
    }

    pub fn getTransformBetween(from: Matrix3x3, to: Matrix3x3) ?Matrix3x3 {
        // Returns a matrix that transforms points from 'from' coordinate system to 'to' coordinate system
        // Formula: transform = to * from.inverse()
        if (from.inverse()) |from_inv| {
            return Matrix3x3.multiply(to, from_inv);
        }
        return null; // from matrix is not invertible
    }
};

// --- Tests ---

// Test identity
test "identity" {
    const m = Matrix3x3.identity();
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3{
        .values = [_]f32{
            1.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
        },
    }, 1e-6));
}

// Test scaling
test "scaling" {
    const m = Matrix3x3.scaling(2.0, 3.0);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3{
        .values = [_]f32{
            2.0, 0.0, 0.0,
            0.0, 3.0, 0.0,
            0.0, 0.0, 1.0,
        },
    }, 1e-6));
}

// Test translation
test "translation" {
    const m = Matrix3x3.translation(5.0, -2.0);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3{
        .values = [_]f32{
            1.0, 0.0, 5.0,
            0.0, 1.0, -2.0,
            0.0, 0.0, 1.0,
        },
    }, 1e-6));
}

// Test rotation
test "rotation" {
    const m = Matrix3x3.rotation(std.math.pi / 2.0);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3{
        .values = [_]f32{
            0.0, -1.0, 0.0,
            1.0, 0.0,  0.0,
            0.0, 0.0,  1.0,
        },
    }, 1e-5));
}

// Test scale (mutating)
test "scale mutating" {
    var m = Matrix3x3.identity();
    m.scale(4.0, 2.0);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3.scaling(4.0, 2.0), 1e-6));
}

// Test rotate (mutating)
test "rotate mutating" {
    var m = Matrix3x3.identity();
    m.rotate(std.math.pi);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3.rotation(std.math.pi), 1e-6));
}

// Test translate (mutating)
test "translate mutating" {
    var m = Matrix3x3.identity();
    m.translate(3.0, 7.0);
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3.translation(3.0, 7.0), 1e-6));
}

// Test transpose (mutating)
test "transpose mutating" {
    var m = Matrix3x3{
        .values = [_]f32{
            1.0, 2.0, 3.0,
            4.0, 5.0, 6.0,
            7.0, 8.0, 9.0,
        },
    };
    m.transpose();
    try std.testing.expect(Matrix3x3.approxEq(m, Matrix3x3{
        .values = [_]f32{
            1.0, 4.0, 7.0,
            2.0, 5.0, 8.0,
            3.0, 6.0, 9.0,
        },
    }, 1e-6));
}

// Test inverse (non-mutating)
test "inverse non-mutating" {
    const m = Matrix3x3.scaling(2.0, 3.0);
    const inv = m.inverse() orelse @panic("Matrix not invertible");
    try std.testing.expect(Matrix3x3.approxEq(inv, Matrix3x3.scaling(0.5, 1.0 / 3.0), 1e-6));
}

// Test point transformation
test "transformPoint" {
    const m = Matrix3x3.translation(10.0, 5.0);
    const pt = m.transformPoint(Point{ .x = 2.0, .y = 3.0 });
    try std.testing.expect(@abs(pt.x - 12.0) < 1e-6);
    try std.testing.expect(@abs(pt.y - 8.0) < 1e-6);
}

// Test transformation between coordinate systems
test "getTransformBetween" {
    // Matrix1: scale by 2
    const matrix1 = Matrix3x3.scaling(2.0, 2.0);
    // Matrix2: translate by (10, 5)
    const matrix2 = Matrix3x3.translation(10.0, 5.0);

    // Get transform from matrix1 space to matrix2 space
    const transform = Matrix3x3.getTransformBetween(matrix1, matrix2) orelse @panic("Transform failed");

    // Test: a point in matrix1 space should transform correctly to matrix2 space
    const point_in_matrix1_space = Point{ .x = 1.0, .y = 1.0 };

    // What this point would be in world space via matrix1
    const world_via_matrix1 = matrix1.transformPoint(point_in_matrix1_space);
    // Should be (2.0, 2.0) due to scaling

    // Transform directly from matrix1 space to matrix2 space
    const point_in_matrix2_space = transform.transformPoint(point_in_matrix1_space);

    // What this point should be when going through matrix2
    const expected_world = matrix2.transformPoint(point_in_matrix2_space);

    // Both should give the same world coordinates
    try std.testing.expect(@abs(world_via_matrix1.x - expected_world.x) < 1e-5);
    try std.testing.expect(@abs(world_via_matrix1.y - expected_world.y) < 1e-5);
}
