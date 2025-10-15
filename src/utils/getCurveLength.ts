import { Point } from 'types'
import getBezierPos from './getBezierPos'

// precision describes how many samples on the curve we want to measure to calculate whole length
// precision = 3, means 3 samples, 0, 0.5, 1. So total distance will be calculate between t = 0 -> t = 0.5, + t = 0.5 -> t = 1

// @return: it's returned as an array of distances divided into precision, for the example above it can return [0, 4, 4 + 3]
export default function getCurveLength(
  p1: Point,
  p2: Point,
  p3: Point,
  p4: Point,
  precision: number
): number[] {
  const distances: number[] = [0]

  for (let i = 0; i < precision; i++) {
    const pointA = getBezierPos(p1, p2, p3, p4, i / precision)
    const pointB = getBezierPos(p1, p2, p3, p4, (i + 1) / precision)
    const distance = Math.hypot(pointA.x - pointB.x, pointA.y - pointB.y)
    const prevDistance = distances[distances.length - 1]
    distances.push(distance + prevDistance)
  }

  return distances
}
