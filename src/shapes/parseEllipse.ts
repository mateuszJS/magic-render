import { BezierCurve } from './types'

interface Point {
  x: number
  y: number
}

export default function parseEllipse(
  cx: number,
  cy: number,
  rx: number,
  ry: number,
  svgHeight: number
): BezierCurve[] {
  // Convert center y-coordinate to Cartesian space
  const centerY = svgHeight - cy

  // Magic number for cubic Bezier approximation of a circle/ellipse
  // This creates a very close approximation using 4 cubic Bezier curves
  const kappa = 0.5522847498307936 // (4/3) * tan(π/8)

  // Calculate control point offsets
  const kx = kappa * rx
  const ky = kappa * ry

  // Define the 8 key points (4 corners + 4 control points for each quadrant)
  const rightPoint: Point = { x: cx + rx, y: centerY }
  const topPoint: Point = { x: cx, y: centerY + ry }
  const leftPoint: Point = { x: cx - rx, y: centerY }
  const bottomPoint: Point = { x: cx, y: centerY - ry }

  // Create four Bezier curves that form the ellipse
  const curves: BezierCurve[] = [
    // First quadrant: right to top
    [
      rightPoint,
      { x: cx + rx, y: centerY + ky }, // control point 1
      { x: cx + kx, y: centerY + ry }, // control point 2
      topPoint,
    ],

    // Second quadrant: top to left
    [
      topPoint,
      { x: cx - kx, y: centerY + ry }, // control point 1
      { x: cx - rx, y: centerY + ky }, // control point 2
      leftPoint,
    ],

    // Third quadrant: left to bottom
    [
      leftPoint,
      { x: cx - rx, y: centerY - ky }, // control point 1
      { x: cx - kx, y: centerY - ry }, // control point 2
      bottomPoint,
    ],

    // Fourth quadrant: bottom to right
    [
      bottomPoint,
      { x: cx + kx, y: centerY - ry }, // control point 1
      { x: cx + rx, y: centerY - ky }, // control point 2
      rightPoint,
    ],
  ]

  return curves
}
