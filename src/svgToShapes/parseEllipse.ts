import { Point } from 'types'

export default function parseEllipse(cx: number, cy: number, rx: number, ry: number): Point[] {
  // Magic number for cubic Bezier approximation of a circle/ellipse
  // This creates a very close approximation using 4 cubic Bezier curves
  const kappa = 0.5522847498307936 // (4/3) * tan(π/8)

  // Calculate control point offsets
  const kx = kappa * rx
  const ky = kappa * ry

  // Define the 8 key points (4 corners + 4 control points for each quadrant)
  const rightPoint: Point = { x: cx + rx, y: cy }
  const topPoint: Point = { x: cx, y: cy + ry }
  const leftPoint: Point = { x: cx - rx, y: cy }
  const bottomPoint: Point = { x: cx, y: cy - ry }

  // Create four Bezier curves that form the ellipse
  // prettier-ignore
  const curves: Point[] = [
    // First quadrant: right to top
    
      rightPoint,
      { x: cx + rx, y: cy + ky }, // control point 1
      { x: cx + kx, y: cy + ry }, // control point 2
      topPoint,

    // Second quadrant: top to left
      { x: cx - kx, y: cy + ry }, // control point 1
      { x: cx - rx, y: cy + ky }, // control point 2
      leftPoint,

    // Third quadrant: left to bottom
      { x: cx - rx, y: cy - ky }, // control point 1
      { x: cx - kx, y: cy - ry }, // control point 2
      bottomPoint,

    // Fourth quadrant: bottom to right
      { x: cx + kx, y: cy - ry }, // control point 1
      { x: cx + rx, y: cy - ky }, // control point 2
  ]

  return curves
}
