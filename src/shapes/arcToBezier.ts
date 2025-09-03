interface BezierCurve {
  cp1x: number
  cp1y: number
  cp2x: number
  cp2y: number
  x: number
  y: number
}

// Convert SVG arc to cubic Bezier curves
export default function arcToBezier(
  x1: number,
  y1: number,
  rx: number,
  ry: number,
  angle: number,
  largeArcFlag: number,
  sweepFlag: number,
  x2: number,
  y2: number
): BezierCurve[] {
  // Handle degenerate cases
  if (rx === 0 || ry === 0 || (x1 === x2 && y1 === y2)) {
    return []
  }

  const radAngle = (angle * Math.PI) / 180
  const cosAngle = Math.cos(radAngle)
  const sinAngle = Math.sin(radAngle)

  // Step 1: Compute (x1', y1')
  const dx2 = (x1 - x2) / 2.0
  const dy2 = (y1 - y2) / 2.0
  const x1p = cosAngle * dx2 + sinAngle * dy2
  const y1p = -sinAngle * dx2 + cosAngle * dy2

  // Step 2: Compute (cx', cy')
  rx = Math.abs(rx)
  ry = Math.abs(ry)
  let rxSq = rx * rx
  let rySq = ry * ry
  const x1pSq = x1p * x1p
  const y1pSq = y1p * y1p

  // Correct radii if needed
  const lambda = x1pSq / rxSq + y1pSq / rySq
  if (lambda > 1) {
    const sqrtLambda = Math.sqrt(lambda)
    rx *= sqrtLambda
    ry *= sqrtLambda
    rxSq = rx * rx
    rySq = ry * ry
  }

  const sign = largeArcFlag === sweepFlag ? -1 : 1
  const numerator = Math.max(0, rxSq * rySq - rxSq * y1pSq - rySq * x1pSq)
  const denominator = rxSq * y1pSq + rySq * x1pSq
  const coeff = denominator === 0 ? 0 : sign * Math.sqrt(numerator / denominator)
  const cxp = coeff * ((rx * y1p) / ry)
  const cyp = coeff * -((ry * x1p) / rx)

  // Step 3: Compute (cx, cy) from (cx', cy')
  const cx = cosAngle * cxp - sinAngle * cyp + (x1 + x2) / 2
  const cy = sinAngle * cxp + cosAngle * cyp + (y1 + y2) / 2

  // Step 4: Compute the angles (theta1, dtheta)
  const ux = (x1p - cxp) / rx
  const uy = (y1p - cyp) / ry
  const vx = (-x1p - cxp) / rx
  const vy = (-y1p - cyp) / ry

  // Calculate theta1
  const n = Math.sqrt(ux * ux + uy * uy)
  let theta1 = n === 0 ? 0 : Math.acos(Math.max(-1, Math.min(1, ux / n)))
  if (uy < 0) theta1 = -theta1

  // Calculate dtheta
  const numer = ux * vx + uy * vy
  const denom = Math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
  let dtheta = denom === 0 ? 0 : Math.acos(Math.max(-1, Math.min(1, numer / denom)))
  if (ux * vy - uy * vx < 0) dtheta = -dtheta

  // Adjust for sweep direction
  if (sweepFlag === 0 && dtheta > 0) {
    dtheta -= 2 * Math.PI
  } else if (sweepFlag === 1 && dtheta < 0) {
    dtheta += 2 * Math.PI
  }

  // Convert arc to Bezier curves
  const segments = Math.max(1, Math.ceil(Math.abs(dtheta) / (Math.PI / 2)))
  const delta = dtheta / segments
  const t =
    Math.abs(delta) < 1e-10
      ? 0
      : ((8 / 3) * Math.sin(delta / 4) * Math.sin(delta / 4)) / Math.sin(delta / 2)

  const curves: BezierCurve[] = []

  for (let i = 0; i < segments; i++) {
    const theta = theta1 + i * delta
    const thetaNext = theta1 + (i + 1) * delta

    const cosTheta = Math.cos(theta)
    const sinTheta = Math.sin(theta)
    const cosThetaNext = Math.cos(thetaNext)
    const sinThetaNext = Math.sin(thetaNext)

    // End point
    const ex = cosThetaNext
    const ey = sinThetaNext

    // Control points
    const q1x = cosTheta - t * sinTheta
    const q1y = sinTheta + t * cosTheta
    const q2x = cosThetaNext + t * sinThetaNext
    const q2y = sinThetaNext - t * cosThetaNext

    // Transform back to original coordinate system
    const cp1x_unrotated = rx * q1x
    const cp1y_unrotated = ry * q1y
    const cp2x_unrotated = rx * q2x
    const cp2y_unrotated = ry * q2y
    const endX_unrotated = rx * ex
    const endY_unrotated = ry * ey

    const cp1x = cx + cosAngle * cp1x_unrotated - sinAngle * cp1y_unrotated
    const cp1y = cy + sinAngle * cp1x_unrotated + cosAngle * cp1y_unrotated
    const cp2x = cx + cosAngle * cp2x_unrotated - sinAngle * cp2y_unrotated
    const cp2y = cy + sinAngle * cp2x_unrotated + cosAngle * cp2y_unrotated

    // For the last segment, use exact endpoint to avoid floating point errors
    const endX =
      i === segments - 1 ? x2 : cx + cosAngle * endX_unrotated - sinAngle * endY_unrotated
    const endY =
      i === segments - 1 ? y2 : cy + sinAngle * endX_unrotated + cosAngle * endY_unrotated

    curves.push({
      cp1x,
      cp1y,
      cp2x,
      cp2y,
      x: endX,
      y: endY,
    })
  }

  return curves
}
