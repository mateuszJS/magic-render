const STRAIGHT_LINE_THRESHOLD = 1e10

export function isStraightHandle(p: Point) {
  return p.x > STRAIGHT_LINE_THRESHOLD
}
