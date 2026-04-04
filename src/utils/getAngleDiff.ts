export default function getAngleDiff(alpha: number, beta: number): number {
  const phi = Math.abs(beta - alpha) % (Math.PI * 2) // This is either the distance or 2*Math.PI - distance
  if (phi > Math.PI) {
    return Math.PI * 2 - phi
  }
  return phi
}
