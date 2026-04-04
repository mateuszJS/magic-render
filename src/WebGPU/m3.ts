
const mat3 = {
  fromMat4(m: Float32Array, dst = new Float32Array(12)) {
    dst[0] = m[0]; dst[1] = m[1];  dst[ 2] = m[ 2]
    dst[4] = m[4]; dst[5] = m[5];  dst[ 6] = m[ 6]
    dst[8] = m[8]; dst[9] = m[9];  dst[10] = m[10]

    return dst
  },
  projection(width: number, height: number, dst = new Float32Array(12)) {
    // Note: This matrix flips the Y axis so that 0 is at the top.
    dst[0] = 2 / width;  dst[1] = 0;             dst[2] = 0
    dst[4] = 0;          dst[5] = -2 / height;   dst[6] = 0
    dst[8] = -1;         dst[9] = 1;             dst[10] = 1
    return dst
  },

  identity(dst = new Float32Array(12)) {
    dst[0] = 1;  dst[1] = 0;  dst[2] = 0
    dst[4] = 0;  dst[5] = 1;  dst[6] = 0
    dst[8] = 0;  dst[9] = 0;  dst[10] = 1
    return dst
  },

  multiply(a: Float32Array, b: Float32Array, dst = new Float32Array(12)) {
    dst = dst || new Float32Array(12)
    const a00 = a[0 * 4 + 0]
    const a01 = a[0 * 4 + 1]
    const a02 = a[0 * 4 + 2]
    const a10 = a[1 * 4 + 0]
    const a11 = a[1 * 4 + 1]
    const a12 = a[1 * 4 + 2]
    const a20 = a[2 * 4 + 0]
    const a21 = a[2 * 4 + 1]
    const a22 = a[2 * 4 + 2]
    const b00 = b[0 * 4 + 0]
    const b01 = b[0 * 4 + 1]
    const b02 = b[0 * 4 + 2]
    const b10 = b[1 * 4 + 0]
    const b11 = b[1 * 4 + 1]
    const b12 = b[1 * 4 + 2]
    const b20 = b[2 * 4 + 0]
    const b21 = b[2 * 4 + 1]
    const b22 = b[2 * 4 + 2]

    dst[ 0] = b00 * a00 + b01 * a10 + b02 * a20
    dst[ 1] = b00 * a01 + b01 * a11 + b02 * a21
    dst[ 2] = b00 * a02 + b01 * a12 + b02 * a22

    dst[ 4] = b10 * a00 + b11 * a10 + b12 * a20
    dst[ 5] = b10 * a01 + b11 * a11 + b12 * a21
    dst[ 6] = b10 * a02 + b11 * a12 + b12 * a22

    dst[ 8] = b20 * a00 + b21 * a10 + b22 * a20
    dst[ 9] = b20 * a01 + b21 * a11 + b22 * a21
    dst[10] = b20 * a02 + b21 * a12 + b22 * a22
    return dst
  },

  translation([tx, ty]: [number, number], dst = new Float32Array(12)) {
    dst[0] = 1;   dst[1] = 0;   dst[2] = 0
    dst[4] = 0;   dst[5] = 1;   dst[6] = 0
    dst[8] = tx;  dst[9] = ty;  dst[10] = 1
    return dst
  },

  rotation(angleInRadians: number, dst = new Float32Array(12)) {
    const c = Math.cos(angleInRadians)
    const s = Math.sin(angleInRadians)

    dst[0] = c;   dst[1] = s;  dst[2] = 0
    dst[4] = -s;  dst[5] = c;  dst[6] = 0
    dst[8] = 0;   dst[9] = 0;  dst[10] = 1
    return dst
  },

  scaling([sx, sy]: [number, number], dst = new Float32Array(12)) {
    dst[0] = sx;  dst[1] = 0;   dst[2] = 0
    dst[4] = 0;   dst[5] = sy;  dst[6] = 0
    dst[8] = 0;   dst[9] = 0;   dst[10] = 1
    return dst
  },

  translate(m: Float32Array, translation: [number, number], dst = new Float32Array(12)) {
    return mat3.multiply(m, mat3.translation(translation), dst)
  },

  rotate(m: Float32Array, angleInRadians: number, dst = new Float32Array(12)) {
    return mat3.multiply(m, mat3.rotation(angleInRadians), dst)
  },

  scale(m: Float32Array, scale: [number, number], dst = new Float32Array(12)) {
    return mat3.multiply(m, mat3.scaling(scale), dst)
  },
}

export default mat3