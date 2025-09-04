/**
 * Get the distance and ratio between two points for radial gradient
 * When shape's boundary has aspect ratio different than 1:1,
 * then scale affect radial gradient angle calculations.
 * Thats why this function exists to eliminate that effect.
 * @param center center of the radius gradient
 * @param vx horizontal radius - distance between center of the gradient and further point on horizontal line(after transforming by angle of radial gradient)
 * @param vy vertical radius - distance between center of the gradient and further point on vertical line(after transforming by angle of radial gradient)
 * @returns The horizontal destination point and the ratio to calculate vertical destination point
 */
export function getCorrectDestinationRatio(
  center: Point,
  vx: Point,
  vy: Point
): {
  destination: Point
  ratio: number
} {
  // Build 2x2 linear map columns in normalized space
  // If degenerate, fall back to simple case
  const lenx = Math.hypot(vx.x, vx.y)
  const leny = Math.hypot(vy.x, vy.y)
  if (lenx < 1e-8 || leny < 1e-8) {
    const horizontal_radius = Math.max(lenx, 1e-8)
    const radius_ratio = lenx > 1e-8 ? leny / lenx : 1
    const destination = {
      x: center.x + (vx.x || 1) * (horizontal_radius / (lenx || 1)),
      y: center.y + (vx.y || 0) * (horizontal_radius / (lenx || 1)),
    }
    return {
      destination,
      ratio: isFinite(radius_ratio) ? radius_ratio : 1,
    }
  }

  // Principal axes via eigen-decomposition of A*A^T where A=[vx vy]
  const Sxx = vx.x * vx.x + vy.x * vy.x
  const Sxy = vx.x * vx.y + vy.x * vy.y
  const Syy = vx.y * vx.y + vy.y * vy.y

  const trace = Sxx + Syy
  const det = Sxx * Syy - Sxy * Sxy
  const tmp = Math.sqrt(Math.max(0, trace * trace * 0.25 - det))

  // Largest then smallest eigenvalue
  const lambda1 = trace * 0.5 + tmp
  const lambda2 = trace * 0.5 - tmp

  const s1 = Math.sqrt(Math.max(lambda1, 0))
  const s2 = Math.sqrt(Math.max(lambda2, 0))

  // Eigenvector for lambda1 (principal axis)
  let ux = 0
  let uy = 0
  if (Math.abs(Sxy) > 1e-8 || Math.abs(lambda1 - Sxx) > 1e-8) {
    // Solve (S - lambda1 I) u = 0; choose a stable component
    if (Math.abs(Sxy) > Math.abs(lambda1 - Sxx)) {
      ux = 1
      uy = (lambda1 - Sxx) / (Sxy || 1e-12)
    } else {
      ux = (Sxy || 1e-12) / (lambda1 - Sxx || 1e-12)
      uy = 1
    }
  } else {
    ux = 1
    uy = 0
  }
  const un = Math.hypot(ux, uy) || 1
  ux /= un
  uy /= un

  // Compose outputs expected by shader
  const destination = { x: center.x + ux * s1, y: center.y + uy * s1 }
  const ratio = s1 > 1e-8 ? s2 / s1 : 1

  return { destination, ratio }
}
