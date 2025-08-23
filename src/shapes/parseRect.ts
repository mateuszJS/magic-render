import { STRAIGHT_LINE_HANDLE } from './const'

export default function parseRect(width: number, height: number, svgHeight: number): Point[] {
  // Define the four corners of the rectangle in Cartesian space
  const topLeft: Point = { x: 0, y: height }
  const topRight: Point = { x: width, y: height }
  const bottomRight: Point = { x: width, y: 0 }
  const bottomLeft: Point = { x: 0, y: 0 }

  // Create four lines that form the rectangle
  // prettier-ignore
  const lines: Point[] = [
    // Top edge: left to right
    topLeft, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, topRight,

    // Right edge: top to bottom
    topRight, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, bottomRight,

    // Bottom edge: right to left
    bottomRight, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, bottomLeft,

    // Left edge: bottom to top
    bottomLeft, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, topLeft,
  ]

  return lines
}
