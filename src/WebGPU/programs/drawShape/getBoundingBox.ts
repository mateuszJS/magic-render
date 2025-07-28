// Calculate real bounding box for a cubic Bézier curve by finding extrema
function calculateCubicBezierRealBounds(p0: Point, p1: Point, p2: Point, p3: Point) {
  // Start with endpoints (t=0 and t=1)
  let minX = Math.min(p0.x, p3.x)
  let maxX = Math.max(p0.x, p3.x)
  let minY = Math.min(p0.y, p3.y)
  let maxY = Math.max(p0.y, p3.y)

  // For cubic Bézier: B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
  // Derivative: B'(t) = 3(1-t)²(P1-P0) + 6(1-t)t(P2-P1) + 3t²(P3-P2)
  // Setting B'(t) = 0 gives us extrema

  // X component extrema
  const a_x = 3 * (p3.x - 3 * p2.x + 3 * p1.x - p0.x)
  const b_x = 6 * (p2.x - 2 * p1.x + p0.x)
  const c_x = 3 * (p1.x - p0.x)

  const extrema_x = solveQuadratic(a_x, b_x, c_x)
  for (const t of extrema_x) {
    if (t > 0 && t < 1) {
      const x = evaluateCubicBezierComponent(t, p0.x, p1.x, p2.x, p3.x)
      minX = Math.min(minX, x)
      maxX = Math.max(maxX, x)
    }
  }

  // Y component extrema
  const a_y = 3 * (p3.y - 3 * p2.y + 3 * p1.y - p0.y)
  const b_y = 6 * (p2.y - 2 * p1.y + p0.y)
  const c_y = 3 * (p1.y - p0.y)

  const extrema_y = solveQuadratic(a_y, b_y, c_y)
  for (const t of extrema_y) {
    if (t > 0 && t < 1) {
      const y = evaluateCubicBezierComponent(t, p0.y, p1.y, p2.y, p3.y)
      minY = Math.min(minY, y)
      maxY = Math.max(maxY, y)
    }
  }

  return { minX, minY, maxX, maxY }
}

// Solve quadratic equation ax² + bx + c = 0
function solveQuadratic(a: number, b: number, c: number): number[] {
  if (Math.abs(a) < 1e-10) {
    // Linear equation: bx + c = 0
    if (Math.abs(b) < 1e-10) return []
    return [-c / b]
  }

  const discriminant = b * b - 4 * a * c
  if (discriminant < 0) return []
  if (Math.abs(discriminant) < 1e-10) return [-b / (2 * a)]

  const sqrt_d = Math.sqrt(discriminant)
  return [(-b + sqrt_d) / (2 * a), (-b - sqrt_d) / (2 * a)]
}

// Evaluate cubic Bézier curve at parameter t for a single component (x or y)
function evaluateCubicBezierComponent(
  t: number,
  p0: number,
  p1: number,
  p2: number,
  p3: number
): number {
  const t2 = t * t
  const t3 = t2 * t
  const oneMinusT = 1 - t
  const oneMinusT2 = oneMinusT * oneMinusT
  const oneMinusT3 = oneMinusT2 * oneMinusT

  return p0 * oneMinusT3 + 3 * p1 * t * oneMinusT2 + 3 * p2 * t2 * oneMinusT + p3 * t3
}

export default function getBoundingBox(curves: Point[], padding: number): Point[] {
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity

  // Calculate REAL bounding box for cubic Bézier curves
  // Assuming curves array contains groups of 4 points (p0, p1, p2, p3) for each cubic Bézier
  const numCubicCurves = Math.floor(curves.length / 3)

  for (let i = 0; i < numCubicCurves; i++) {
    const p0 = curves[i * 3 + 0]
    const p1 = curves[i * 3 + 1]
    const p2 = curves[i * 3 + 2]
    const p3 = curves[i * 3 + 3]

    // Calculate real bounding box for this cubic Bézier curve
    const bounds = calculateCubicBezierRealBounds(p0, p1, p2, p3)

    minX = Math.min(minX, bounds.minX)
    minY = Math.min(minY, bounds.minY)
    maxX = Math.max(maxX, bounds.maxX)
    maxY = Math.max(maxY, bounds.maxY)
  }

  return [
    { x: minX - padding, y: minY - padding }, // bottom-left
    { x: maxX + padding, y: minY - padding }, // bottom-right
    { x: maxX + padding, y: maxY + padding }, // top-right
    { x: minX - padding, y: maxY + padding }, // top-left
  ]
}
