import { Segment, Point, CubicBezier, Line } from 'types'

interface PathCommand {
  command: string
  args: number[]
}

// Calculate the length of a line segment
function getLineLength(p1: Point, p2: Point): number {
  return Math.hypot(p2.x - p1.x, p2.y - p1.y)
}

// Get length of a path using SVG's native getTotalLength()
function getPathLength(pathData: string): number {
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path')
  path.setAttribute('d', pathData)

  const length = path.getTotalLength()
  console.log(length)
  return length
}

// Calculate the approximate length of a cubic Bezier curve by converting to path
function getCubicBezierLength(p0: Point, p1: Point, p2: Point, p3: Point): number {
  const pathData = `M ${p0.x} ${p0.y} C ${p1.x} ${p1.y} ${p2.x} ${p2.y} ${p3.x} ${p3.y}`
  return getPathLength(pathData)
}

function parsePathData(pathData: string): PathCommand[] {
  // Remove whitespace and split by command letters
  const commands: PathCommand[] = []
  const commandRegex = /([MmLlHhVvCcSsQqTtAaZz])\s*([^MmLlHhVvCcSsQqTtAaZz]*)/g

  let match
  while ((match = commandRegex.exec(pathData)) !== null) {
    const command = match[1]
    const argsString = match[2].trim()

    // Parse numeric arguments
    const args: number[] = []
    if (argsString) {
      const numbers = argsString.match(/-?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?/g)
      if (numbers) {
        args.push(...numbers.map(parseFloat))
      }
    }

    commands.push({ command, args })
  }

  return commands
}

function commandsToSegments(commands: PathCommand[]): Segment[] {
  const segments: Segment[] = []
  let currentPoint: Point = { x: 0, y: 0 }
  let pathStart: Point = { x: 0, y: 0 }
  let lastControlPoint: Point | null = null

  for (const { command, args } of commands) {
    switch (command.toLowerCase()) {
      case 'm': {
        // MoveTo
        const isRelative = command === 'm'
        for (let i = 0; i < args.length; i += 2) {
          const x = args[i] + (isRelative && i > 0 ? currentPoint.x : 0)
          const y = args[i + 1] + (isRelative && i > 0 ? currentPoint.y : 0)

          if (i === 0) {
            // First move is absolute for both M and m
            currentPoint = {
              x: isRelative ? currentPoint.x + args[i] : args[i],
              y: isRelative ? currentPoint.y + args[i + 1] : args[i + 1],
            }
            pathStart = { ...currentPoint }
          } else {
            // Subsequent moves are treated as LineTo
            const newPoint = { x, y }
            const line: Line = [currentPoint, newPoint]
            segments.push({
              points: line,
              length: getLineLength(currentPoint, newPoint),
            })
            currentPoint = newPoint
          }
        }
        lastControlPoint = null
        break
      }

      case 'l': {
        // LineTo
        const isRelative = command === 'l'
        for (let i = 0; i < args.length; i += 2) {
          const newPoint: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const line: Line = [currentPoint, newPoint]
          segments.push({
            points: line,
            length: getLineLength(currentPoint, newPoint),
          })
          currentPoint = newPoint
        }
        lastControlPoint = null
        break
      }

      case 'h': {
        // Horizontal LineTo
        const isRelative = command === 'h'
        for (const x of args) {
          const newPoint: Point = {
            x: x + (isRelative ? currentPoint.x : 0),
            y: currentPoint.y,
          }
          const line: Line = [currentPoint, newPoint]
          segments.push({
            points: line,
            length: getLineLength(currentPoint, newPoint),
          })
          currentPoint = newPoint
        }
        lastControlPoint = null
        break
      }

      case 'v': {
        // Vertical LineTo
        const isRelative = command === 'v'
        for (const y of args) {
          const newPoint: Point = {
            x: currentPoint.x,
            y: y + (isRelative ? currentPoint.y : 0),
          }
          const line: Line = [currentPoint, newPoint]
          segments.push({
            points: line,
            length: getLineLength(currentPoint, newPoint),
          })
          currentPoint = newPoint
        }
        lastControlPoint = null
        break
      }

      case 'c': {
        // Cubic Bezier
        const isRelative = command === 'c'
        for (let i = 0; i < args.length; i += 6) {
          const cp1: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const cp2: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: args[i + 3] + (isRelative ? currentPoint.y : 0),
          }
          const endPoint: Point = {
            x: args[i + 4] + (isRelative ? currentPoint.x : 0),
            y: args[i + 5] + (isRelative ? currentPoint.y : 0),
          }

          const cubicBezier: CubicBezier = [currentPoint, cp1, cp2, endPoint]
          segments.push({
            points: cubicBezier,
            length: getCubicBezierLength(currentPoint, cp1, cp2, endPoint),
          })
          currentPoint = endPoint
          lastControlPoint = cp2
        }
        break
      }

      case 's': {
        // Smooth Cubic Bezier
        const isRelative = command === 's'
        for (let i = 0; i < args.length; i += 4) {
          // First control point is reflection of last control point
          const cp1: Point = lastControlPoint
            ? {
                x: 2 * currentPoint.x - lastControlPoint.x,
                y: 2 * currentPoint.y - lastControlPoint.y,
              }
            : { ...currentPoint }

          const cp2: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const endPoint: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: args[i + 3] + (isRelative ? currentPoint.y : 0),
          }

          const cubicBezier: CubicBezier = [currentPoint, cp1, cp2, endPoint]
          segments.push({
            points: cubicBezier,
            length: getCubicBezierLength(currentPoint, cp1, cp2, endPoint),
          })
          currentPoint = endPoint
          lastControlPoint = cp2
        }
        break
      }

      case 'z': {
        // ClosePath
        if (currentPoint.x !== pathStart.x || currentPoint.y !== pathStart.y) {
          const line: Line = [currentPoint, pathStart]
          segments.push({
            points: line,
            length: getLineLength(currentPoint, pathStart),
          })
        }
        currentPoint = pathStart
        lastControlPoint = null
        break
      }

      // Note: Q, T, A commands not implemented yet (quadratic bezier and arc)
      default:
        console.warn(`SVG path command '${command}' not supported yet`)
        lastControlPoint = null
    }
  }

  return segments
}

enum EdgeColor {
  BLACK = 0,
  RED = 1,
  GREEN = 2,
  YELLOW = 3,
  BLUE = 4,
  MAGENTA = 5,
  CYAN = 6,
  WHITE = 7,
}

type Seed = {
  value: number
}

function seedExtract3(seed: Seed): number {
  const v = Math.trunc(seed.value % 3)
  seed.value /= 3
  return v
}

function initColor(seed: Seed): EdgeColor {
  const colors = [EdgeColor.CYAN, EdgeColor.MAGENTA, EdgeColor.YELLOW]
  return colors[seedExtract3(seed)]
}

function mix(a: Point, b: Point, t: number): Point {
  return {
    x: a.x * (1 - t) + b.x * t,
    y: a.y * (1 - t) + b.y * t,
  }
}

function substract(a: Point, b: Point): Point {
  return {
    x: a.x - b.x,
    y: a.y - b.y,
  }
}

function floatIsEqual(a: number, b: number): boolean {
  return Math.abs(a - b) < Number.EPSILON
}

function direction(segment: Segment, param: number): Point {
  const [p0, p1, p2, p3] = segment.points as Point[]

  const tangent = mix(
    mix(substract(p1, p0), substract(p2, p1), param),
    mix(substract(p2, p1), substract(p3, p2), param),
    param
  )
  if (floatIsEqual(tangent.x, 0) && floatIsEqual(tangent.y, 0)) {
    if (floatIsEqual(param, 0)) {
      return substract(p2, p0)
    }
    if (floatIsEqual(param, 1)) {
      return substract(p3, p1)
    }
  }
  return tangent
}

export default function svgToSegments(svg: string): Segment[] {
  const segments: Segment[] = []

  // Parse SVG string using DOMParser
  const parser = new DOMParser()
  const svgDoc = parser.parseFromString(svg, 'image/svg+xml')

  // Find all path elements
  const pathElements = svgDoc.querySelectorAll('path')

  for (const pathElement of pathElements) {
    const pathData = pathElement.getAttribute('d')
    if (pathData) {
      const commands = parsePathData(pathData)
      const pathSegments = commandsToSegments(commands)

      // If we want the total length of the entire path, we could use:
      // const totalPathLength = getPathLength(pathData)
      // But since we're breaking it into segments, we calculate individual lengths

      segments.push(...pathSegments)
    }
  }

  // Find all line elements
  const lineElements = svgDoc.querySelectorAll('line')
  for (const lineElement of lineElements) {
    const x1 = parseFloat(lineElement.getAttribute('x1') || '0')
    const y1 = parseFloat(lineElement.getAttribute('y1') || '0')
    const x2 = parseFloat(lineElement.getAttribute('x2') || '0')
    const y2 = parseFloat(lineElement.getAttribute('y2') || '0')

    const p1: Point = { x: x1, y: y1 }
    const p2: Point = { x: x2, y: y2 }
    const line: Line = [p1, p2]

    segments.push({
      points: line,
      length: getLineLength(p1, p2),
    })
  }

  // Find all polyline elements
  const polylineElements = svgDoc.querySelectorAll('polyline')
  for (const polylineElement of polylineElements) {
    const pointsAttr = polylineElement.getAttribute('points')
    if (pointsAttr) {
      const coords = pointsAttr
        .trim()
        .split(/[\s,]+/)
        .map(parseFloat)
      for (let i = 0; i < coords.length - 2; i += 2) {
        const p1: Point = { x: coords[i], y: coords[i + 1] }
        const p2: Point = { x: coords[i + 2], y: coords[i + 3] }
        const line: Line = [p1, p2]
        segments.push({
          points: line,
          length: getLineLength(p1, p2),
        })
      }
    }
  }

  // Find all polygon elements
  const polygonElements = svgDoc.querySelectorAll('polygon')
  for (const polygonElement of polygonElements) {
    const pointsAttr = polygonElement.getAttribute('points')
    if (pointsAttr) {
      const coords = pointsAttr
        .trim()
        .split(/[\s,]+/)
        .map(parseFloat)
      for (let i = 0; i < coords.length - 2; i += 2) {
        const p1: Point = { x: coords[i], y: coords[i + 1] }
        const p2: Point = { x: coords[i + 2], y: coords[i + 3] }
        const line: Line = [p1, p2]
        segments.push({
          points: line,
          length: getLineLength(p1, p2),
        })
      }
      // Close the polygon
      if (coords.length >= 4) {
        const first: Point = { x: coords[0], y: coords[1] }
        const last: Point = { x: coords[coords.length - 2], y: coords[coords.length - 1] }
        const line: Line = [last, first]
        segments.push({
          points: line,
          length: getLineLength(last, first),
        })
      }
    }
  }

  return segments
}
