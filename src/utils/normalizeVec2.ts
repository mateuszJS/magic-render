export default function normalizeVec2(vec: Point): Point {
  const length = Math.sqrt(vec.x * vec.x + vec.y * vec.y)
  return {
    x: vec.x / length,
    y: vec.y / length,
  }
}
