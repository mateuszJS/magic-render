import normalizeVec2 from './normalizeVec2'

export default function getBezierTan(p1: Point, p2: Point, p3: Point, p4: Point, t: number): Point {
  const t2 = t * t
  const one_minus_t = 1.0 - t
  const one_minus_t2 = one_minus_t * one_minus_t

  return normalizeVec2({
    x: one_minus_t2 * (p2.x - p1.x) + 2.0 * t * one_minus_t * (p3.x - p2.x) + t2 * (p4.x - p3.x),
    y: one_minus_t2 * (p2.y - p1.y) + 2.0 * t * one_minus_t * (p3.y - p2.y) + t2 * (p4.y - p3.y),
  })
}
