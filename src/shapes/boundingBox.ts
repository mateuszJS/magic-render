interface Point {
  x: number
  y: number
}

/**
 * Represents a 2D bounding box with minimum and maximum coordinates.
 */
class BoundingBox {
  min_x: number = Infinity
  min_y: number = Infinity
  max_x: number = -Infinity
  max_y: number = -Infinity

  constructor(points?: Point[]) {
    if (points) {
      points.forEach((p) => this.addPoint(p))
    }
  }

  addPoint(p: Point) {
    this.min_x = Math.min(this.min_x, p.x)
    this.min_y = Math.min(this.min_y, p.y)
    this.max_x = Math.max(this.max_x, p.x)
    this.max_y = Math.max(this.max_y, p.y)
  }

  addBox(box: BoundingBox) {
    this.min_x = Math.min(this.min_x, box.min_x)
    this.min_y = Math.min(this.min_y, box.min_y)
    this.max_x = Math.max(this.max_x, box.max_x)
    this.max_y = Math.max(this.max_y, box.max_y)
  }
}

const STRAIGHT_LINE_THRESHOLD = 1e10

/**
 * Solves the quadratic equation ax² + bx + c = 0.
 * @returns An array with 0, 1, or 2 solutions.
 */
function solveQuadratic(a: number, b: number, c: number): number[] {
  const epsilon = 1e-10

  if (Math.abs(a) < epsilon) {
    // Linear equation: bx + c = 0
    return Math.abs(b) < epsilon ? [] : [-c / b]
  }

  const discriminant = b * b - 4.0 * a * c
  if (discriminant < -epsilon) {
    return [] // No real solutions
  }

  if (Math.abs(discriminant) < epsilon) {
    return [-b / (2.0 * a)] // One solution (repeated root)
  }

  const sqrt_d = Math.sqrt(discriminant)
  return [(-b + sqrt_d) / (2.0 * a), (-b - sqrt_d) / (2.0 * a)] // Two solutions
}

/**
 * Evaluates a cubic Bézier curve at parameter t for a single component (x or y).
 * Uses the standard cubic Bézier formula: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
 */
function evaluateCubicBezierComponent(
  t: number,
  p0: number,
  p1: number,
  p2: number,
  p3: number
): number {
  const t2 = t * t
  const t3 = t2 * t
  const one_minus_t = 1.0 - t
  const one_minus_t2 = one_minus_t * one_minus_t
  const one_minus_t3 = one_minus_t2 * one_minus_t

  return p0 * one_minus_t3 + 3.0 * p1 * t * one_minus_t2 + 3.0 * p2 * t2 * one_minus_t + p3 * t3
}

/**
 * Calculates the precise bounding box for a cubic Bézier curve by finding its extrema.
 */
function calculateCubicBezierRealBounds(p0: Point, p1: Point, p2: Point, p3: Point): BoundingBox {
  let min_x = Math.min(p0.x, p3.x)
  let max_x = Math.max(p0.x, p3.x)
  let min_y = Math.min(p0.y, p3.y)
  let max_y = Math.max(p0.y, p3.y)

  // For cubic Bézier: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
  // Derivative B'(t) is a quadratic equation. Roots of B'(t)=0 give extrema.
  // We can find the coefficients of the quadratic equation a*t^2 + b*t + c = 0
  const ax = 3 * (-p0.x + 3 * p1.x - 3 * p2.x + p3.x)
  const bx = 6 * (p0.x - 2 * p1.x + p2.x)
  const cx = 3 * (-p0.x + p1.x)

  solveQuadratic(ax, bx, cx).forEach((t) => {
    if (t > 0.0 && t < 1.0) {
      const x = evaluateCubicBezierComponent(t, p0.x, p1.x, p2.x, p3.x)
      min_x = Math.min(min_x, x)
      max_x = Math.max(max_x, x)
    }
  })

  const ay = 3 * (-p0.y + 3 * p1.y - 3 * p2.y + p3.y)
  const by = 6 * (p0.y - 2 * p1.y + p2.y)
  const cy = 3 * (-p0.y + p1.y)

  solveQuadratic(ay, by, cy).forEach((t) => {
    if (t > 0.0 && t < 1.0) {
      const y = evaluateCubicBezierComponent(t, p0.y, p1.y, p2.y, p3.y)
      min_y = Math.min(min_y, y)
      max_y = Math.max(max_y, y)
    }
  })

  const box = new BoundingBox()
  box.min_x = min_x
  box.min_y = min_y
  box.max_x = max_x
  box.max_y = max_y
  return box
}

/**
 * Gets the bounding box for all paths.
 */
export function getBoundingBox(paths: Point[][]): BoundingBox {
  const totalBox = new BoundingBox()

  paths.forEach((path) => {
    const pathBox = getBoundingBoxForPath(path)
    totalBox.addBox(pathBox)
  })

  return totalBox
}

/**
 * Gets the bounding box from a path represented by an array of points.
 * The point structure is [anchor, handle, handle, anchor, handle, handle, anchor, ...].
 * For closed paths, the last two points are handles connecting the last anchor to the first.
 */
function getBoundingBoxForPath(path: Point[]): BoundingBox {
  if (path.length < 4) {
    return new BoundingBox(path)
  }
  const isClosed = path.length % 3 === 0

  const totalBox = new BoundingBox()
  const numSegments = Math.floor((path.length - 1) / 3)

  for (let i = 0; i < numSegments; i++) {
    const p0 = path[i * 3]
    const p3 = path[i * 3 + 3]
    const p1 = path[i * 3 + 1].x > STRAIGHT_LINE_THRESHOLD ? p0 : path[i * 3 + 1]
    const p2 = path[i * 3 + 2].x > STRAIGHT_LINE_THRESHOLD ? p3 : path[i * 3 + 2]

    const segmentBox = calculateCubicBezierRealBounds(p0, p1, p2, p3)
    totalBox.addBox(segmentBox)
  }

  // Handle the closing segment for a closed path
  if (isClosed && path.length > 1) {
    const p0 = path[path.length - 3]
    const p3 = path[0]
    const p1 = path[path.length - 2].x > STRAIGHT_LINE_THRESHOLD ? p0 : path[path.length - 2]
    const p2 = path[path.length - 1].x > STRAIGHT_LINE_THRESHOLD ? p3 : path[path.length - 1]

    const segmentBox = calculateCubicBezierRealBounds(p0, p1, p2, p3)
    totalBox.addBox(segmentBox)
  }

  return totalBox
}
