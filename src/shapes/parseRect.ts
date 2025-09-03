import { STRAIGHT_LINE_HANDLE } from './const'

export default function parseRect(x: number, y: number, width: number, height: number): Point[] {
  // Define the four corners of the rectangle in Cartesian space
  const topLeft: Point = { x, y: y + height }
  const topRight: Point = { x: x + width, y: y + height }
  const bottomRight: Point = { x: x + width, y }
  const bottomLeft: Point = { x, y }

  // Create four lines that form the rectangle
  // prettier-ignore
  const lines: Point[] = [
    // Top edge: left to right
    topLeft, STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, topRight,

    // Right edge: top to bottom
    STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, bottomRight,

    // Bottom edge: right to left
    STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, bottomLeft,

    // Left edge: bottom to top
    STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE,
  ]

  return lines
}
