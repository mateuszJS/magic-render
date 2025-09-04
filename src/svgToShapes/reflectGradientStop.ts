export default function reflectGradientStops(
  svgHeight: number,
  rawStart: Point,
  rawEnd: Point,
  bb: BoundingBox
): { start: Point; end: Point } {
  const reflectedStart = {
    x: rawStart.x,
    y: svgHeight - rawStart.y,
  }
  const reflectedEnd = { x: rawEnd.x, y: svgHeight - rawEnd.y }

  // Normalize to bounding box space for shader
  const bbw = bb.max_x - bb.min_x || 1
  const bbh = bb.max_y - bb.min_y || 1
  const start = {
    x: (reflectedStart.x - bb.min_x) / bbw,
    y: (reflectedStart.y - bb.min_y) / bbh,
  }
  const end = {
    x: (reflectedEnd.x - bb.min_x) / bbw,
    y: (reflectedEnd.y - bb.min_y) / bbh,
  }

  return { start, end }
}
