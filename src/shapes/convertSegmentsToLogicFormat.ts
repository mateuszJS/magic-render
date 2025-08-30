import { STRAIGHT_LINE_HANDLE } from './const'

// Convert Paper.js path segments to Logic module format
export default function convertSegmentsToLogicFormat(
  segments: paper.Segment[],
  closed: boolean
): { x: number; y: number }[] {
  const points: { x: number; y: number }[] = []

  for (let i = 0; i < segments.length; i++) {
    const segment = segments[i]
    const nextSegment = segments[(i + 1) % segments.length]

    // Add the control point (anchor)
    points.push({ x: segment.point.x, y: segment.point.y })

    // Check if this segment has handleOut
    const hasHandleOut =
      segment.handleOut && (segment.handleOut.x !== 0 || segment.handleOut.y !== 0)
    if (hasHandleOut) {
      points.push({
        x: segment.point.x + segment.handleOut.x,
        y: segment.point.y + segment.handleOut.y,
      })
    } else {
      points.push(STRAIGHT_LINE_HANDLE)
    }

    // For the last segment in a closed path, don't add the next segment's handleIn
    // because it connects back to the start
    if (closed && i === segments.length - 1) {
      // Check if the first segment has handleIn (connection back to start)
      const firstSegment = segments[0]
      const hasHandleIn =
        firstSegment.handleIn && (firstSegment.handleIn.x !== 0 || firstSegment.handleIn.y !== 0)
      if (hasHandleIn) {
        points.push({
          x: firstSegment.point.x + firstSegment.handleIn.x,
          y: firstSegment.point.y + firstSegment.handleIn.y,
        })
      } else {
        points.push(STRAIGHT_LINE_HANDLE)
      }
      break // Don't add the control point again
    }

    // Check if the next segment has handleIn
    const hasHandleIn =
      nextSegment &&
      nextSegment.handleIn &&
      (nextSegment.handleIn.x !== 0 || nextSegment.handleIn.y !== 0)
    if (hasHandleIn && nextSegment) {
      points.push({
        x: nextSegment.point.x + nextSegment.handleIn.x,
        y: nextSegment.point.y + nextSegment.handleIn.y,
      })
    } else {
      points.push(STRAIGHT_LINE_HANDLE)
    }
  }

  return points
}
