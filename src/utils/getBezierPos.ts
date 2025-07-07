export default function getBezierPos(p1: Point, p2: Point, p3: Point, p4: Point, t: number): Point {
  const t2 = t * t
  const one_minus_t = 1.0 - t
  const one_minus_t2 = one_minus_t * one_minus_t

  // vec2 pos = p1 * one_minus_t2 * one_minus_t + p2 * 3.0 * t * one_minus_t2 + p3 * 3.0 * t2 * one_minus_t + p4 * t2 * t;
  return {
    x:
      p1.x * one_minus_t2 * one_minus_t +
      p2.x * 3.0 * t * one_minus_t2 +
      p3.x * 3.0 * t2 * one_minus_t +
      p4.x * t2 * t,
    y:
      p1.y * one_minus_t2 * one_minus_t +
      p2.y * 3.0 * t * one_minus_t2 +
      p3.y * 3.0 * t2 * one_minus_t +
      p4.y * t2 * t,
  }
}
