
const vec3 = {
  cross(a: number[] | Float32Array, b: number[] | Float32Array, dst = new Float32Array(3)) {
    const t0 = a[1] * b[2] - a[2] * b[1]
    const t1 = a[2] * b[0] - a[0] * b[2]
    const t2 = a[0] * b[1] - a[1] * b[0]

    dst[0] = t0
    dst[1] = t1
    dst[2] = t2

    return dst
  },

  subtract(a: number[] | Float32Array, b: number[] | Float32Array, dst = new Float32Array(3)) {
    dst[0] = a[0] - b[0]
    dst[1] = a[1] - b[1]
    dst[2] = a[2] - b[2]

    return dst
  },

  normalize(v : number[] | Float32Array, dst = new Float32Array(3)) {
    const length = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    // make sure we don't divide by 0.
    if (length > 0.00001) {
      dst[0] = v[0] / length
      dst[1] = v[1] / length
      dst[2] = v[2] / length
    } else {
      dst[0] = 0
      dst[1] = 0
      dst[2] = 0
    }

    return dst
  },
}

export default vec3