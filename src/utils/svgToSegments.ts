import { Segment, Point, CubicBezier, Line } from 'types'

interface PathCommand {
  command: string
  args: number[]
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
            segments.push([currentPoint, newPoint] as Line)
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
          segments.push([currentPoint, newPoint] as Line)
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
          segments.push([currentPoint, newPoint] as Line)
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
          segments.push([currentPoint, newPoint] as Line)
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

          segments.push([currentPoint, cp1, cp2, endPoint] as CubicBezier)
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

          segments.push([currentPoint, cp1, cp2, endPoint] as CubicBezier)
          currentPoint = endPoint
          lastControlPoint = cp2
        }
        break
      }

      case 'z': {
        // ClosePath
        if (currentPoint.x !== pathStart.x || currentPoint.y !== pathStart.y) {
          segments.push([currentPoint, pathStart] as Line)
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

    segments.push([
      { x: x1, y: y1 },
      { x: x2, y: y2 },
    ] as Line)
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
        segments.push([p1, p2] as Line)
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
        segments.push([p1, p2] as Line)
      }
      // Close the polygon
      if (coords.length >= 4) {
        const first: Point = { x: coords[0], y: coords[1] }
        const last: Point = { x: coords[coords.length - 2], y: coords[coords.length - 1] }
        segments.push([last, first] as Line)
      }
    }
  }

  return segments
}
