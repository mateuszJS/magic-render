// Matrix3x3 implementation for 2D affine transforms
const std = @import("std");
const Point = @import("types.zig").Point;
const PointUV = @import("types.zig").PointUV;

pub const Matrix3x3 = struct {
    values: [9]f32,

    pub fn from(values: [9]f32) Matrix3x3 {
        return Matrix3x3{ .values = values };
    }

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
        if (@abs(det) < 1e-6) @panic("Matrix not invertible");
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

    pub fn get(self: Matrix3x3, p: anytype) Point {
        // Applies the matrix to a 2D point (x, y) and returns the transformed point
        const m = self.values;
        const tx = m[0] * p.x + m[1] * p.y + m[2];
        const ty = m[3] * p.x + m[4] * p.y + m[5];
        // For affine matrices, w is always 1, but for completeness:
        // const tw = m[6] * x + m[7] * y + m[8];
        return Point{ .x = tx, .y = ty };
    }

    pub fn getUV(self: Matrix3x3, p: PointUV) PointUV {
        // Applies the matrix to a 2D point (x, y) and returns the transformed point
        const m = self.values;
        const tx = m[0] * p.x + m[1] * p.y + m[2];
        const ty = m[3] * p.x + m[4] * p.y + m[5];
        // For affine matrices, w is always 1, but for completeness:
        // const tw = m[6] * x + m[7] * y + m[8];
        return PointUV{ .x = tx, .y = ty, .u = p.u, .v = p.v };
    }

    pub fn getRotationAngle(self: Matrix3x3) f32 {
        // Extract rotation angle from the matrix
        // For a 2D rotation matrix, the angle can be calculated using atan2
        const m = self.values;
        return std.math.atan2(m[3], m[0]); // atan2(sin, cos)
    }

    pub fn getTransformBetween(m: Matrix3x3, to: Matrix3x3) Matrix3x3 {
        // Returns a matrix that transforms points from 'from' coordinate system to 'to' coordinate system
        // Formula: transform = to * from.inverse()
        return Matrix3x3.multiply(to, m.inverse());
    }

    // This function calculates a 3x3 transformation matrix that maps a unit square
    // to a given rectangle (or any parallelogram).
    //
    // Unit Square (neutral state):
    // (0,1) tl ------ tr (1,1)
    //   |              |
    //   |              |
    // (0,0) bl ------ br (1,0)
    //
    // The input points for the target rectangle must be in the following order:
    // rect_points[0]: top-left corner
    // rect_points[1]: top-right corner
    // rect_points[2]: bottom-right corner
    // rect_points[3]: bottom-left corner
    // It's standard CSS order of corners.
    pub fn getMatrixFromRectangle(rect_points: [4]PointUV) Matrix3x3 {
        const p_tl = rect_points[0];
        const p_br = rect_points[2];
        const p_bl = rect_points[3];

        // The transformation matrix maps the unit square's basis vectors (1,0) and (0,1)
        // to the sides of the target rectangle, and maps the origin (0,0) to the
        // bottom-left corner of the target rectangle.

        // Vector for the transformed x-axis (from bottom-left to bottom-right)
        const x_axis_vec = Point{ .x = p_br.x - p_bl.x, .y = p_br.y - p_bl.y };

        // Vector for the transformed y-axis (from bottom-left to top-left)
        const y_axis_vec = Point{ .x = p_tl.x - p_bl.x, .y = p_tl.y - p_bl.y };

        // The origin of the transformed coordinate system is the bottom-left corner.
        const origin = p_bl;

        // Construct the 3x3 affine transformation matrix:
        // [ x_axis_vec.x  y_axis_vec.x  origin.x ]
        // [ x_axis_vec.y  y_axis_vec.y  origin.y ]
        // [      0             0           1      ]
        return Matrix3x3.from([_]f32{
            x_axis_vec.x, y_axis_vec.x, origin.x,
            x_axis_vec.y, y_axis_vec.y, origin.y,
            0.0,          0.0,          1.0,
        });
    }

    // Creates a transformation matrix with position and rotation but no scale (scale = 1).
    // This function extracts the rotation angle from the rectangle's orientation and
    // positions the unit square at the rectangle's top-left corner.
    //
    // The input points for the target rectangle must be in the following order:
    // rect_points[0]: top-left corner
    // rect_points[1]: top-right corner
    // rect_points[2]: bottom-right corner
    // rect_points[3]: bottom-left corner
    pub fn getMatrixFromRectangleNoScale(rect_points: [4]PointUV) Matrix3x3 {
        const p_tl = rect_points[0];
        const p_tr = rect_points[1];

        // Calculate rotation angle from the top edge vector
        const top_edge = Point{ .x = p_tr.x - p_tl.x, .y = p_tr.y - p_tl.y };
        const rotation_angle = std.math.atan2(top_edge.y, top_edge.x);

        // Simple approach: just translate to top-left and rotate
        // This should be completely stable with no accumulation
        return Matrix3x3.from([_]f32{
            std.math.cos(rotation_angle), -std.math.sin(rotation_angle), p_tl.x,
            std.math.sin(rotation_angle), std.math.cos(rotation_angle),  p_tl.y,
            0.0,                          0.0,                           1.0,
        });
    } // scales the matrix around a pivot point (px, py
    pub fn pivotScale(self: *Matrix3x3, sx: f32, sy: f32, px: f32, py: f32) void {
        self.* = Matrix3x3.multiply(self.*, Matrix3x3.from([_]f32{
            sx, 0,  px * (1 - sx),
            0,  sy, py * (1 - sy),
            0,  0,  1,
        }));
    }

    // this function rotated by the angle which is not uniform in x and y axis
    // so for example x or y is scaled, so angle should be also adjusted
    pub fn rotateScaled(self: *Matrix3x3, angle_rad: f32, aspect: f32) void {
        const c = std.math.cos(angle_rad);
        const s = std.math.sin(angle_rad);
        self.* = Matrix3x3.multiply(self.*, Matrix3x3.from([_]f32{
            c,          -s / aspect, 0.0,
            s * aspect, c,           0.0,
            0.0,        0.0,         1.0,
        }));
    }

    // Returns true if the transformation causes a reflection (i.e., the coordinate system is flipped).
    pub fn isMirrored(self: Matrix3x3) bool {
        const det = self.values[0] * self.values[4] - self.values[1] * self.values[3];
        return det < 0;
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
test "get" {
    const m = Matrix3x3.translation(10.0, 5.0);
    const pt = m.get(Point{ .x = 2.0, .y = 3.0 });
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
    const world_via_matrix1 = matrix1.get(point_in_matrix1_space);
    // Should be (2.0, 2.0) due to scaling

    // Transform directly from matrix1 space to matrix2 space
    const point_in_matrix2_space = transform.get(point_in_matrix1_space);

    // What this point should be when going through matrix2
    const expected_world = matrix2.get(point_in_matrix2_space);

    // Both should give the same world coordinates
    try std.testing.expect(@abs(world_via_matrix1.x - expected_world.x) < 1e-5);
    try std.testing.expect(@abs(world_via_matrix1.y - expected_world.y) < 1e-5);
}
