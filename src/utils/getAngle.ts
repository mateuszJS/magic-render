import { Point } from 'types'

export default function getAngle(from: Point, to: Point) {
  return Math.atan2(to.y - from.y, to.x - from.x)
}
