export default function getDistance(p1: Point, p2: Point) {
  return Math.hypot(p1.x - p2.x, p1.y - p2.y)
}
