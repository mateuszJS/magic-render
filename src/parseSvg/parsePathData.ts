import { STRAIGHT_LINE_HANDLE } from './const'
import { Line, BezierCurve, PathSegment } from './types'

interface PathCommand {
  command: string
  args: number[]
}

function getDataPathCommands(pathData: string): PathCommand[] {
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

function reflectY(y: number, svgHeight: number): number {
  return svgHeight - y
}

function commandsToSegments(commands: PathCommand[], svgHeight: number): PathSegment[][] {
  const allPaths: PathSegment[][] = []

  let currentSegments: PathSegment[] = []
  let currentPoint: Point = { x: 0, y: reflectY(0, svgHeight) }
  let pathStart: Point = { x: 0, y: reflectY(0, svgHeight) }
  let lastControlPoint: Point | null = null

  const finishCurrentPath = () => {
    if (currentSegments.length > 0) {
      allPaths.push([...currentSegments])
      currentSegments = []
    }
  }

  for (const { command, args } of commands) {
    switch (command.toLowerCase()) {
      case 'm': {
        // MoveTo - start a new sub-path if we have existing segments
        if (currentSegments.length > 0) {
          finishCurrentPath()
        }

        const isRelative = command === 'm'
        for (let i = 0; i < args.length; i += 2) {
          if (i === 0) {
            // First move is absolute for both M and m
            currentPoint = {
              x: isRelative ? currentPoint.x + args[i] : args[i],
              y: isRelative ? currentPoint.y - args[i + 1] : reflectY(args[i + 1], svgHeight),
            }
            pathStart = { ...currentPoint }
          } else {
            // Subsequent moves are treated as LineTo
            const newPoint = {
              x: args[i] + (isRelative ? currentPoint.x : 0),
              y: isRelative ? currentPoint.y - args[i + 1] : reflectY(args[i + 1], svgHeight),
            }
            const lineSegment: Line = [
              currentPoint,
              STRAIGHT_LINE_HANDLE,
              STRAIGHT_LINE_HANDLE,
              newPoint,
            ]
            currentSegments.push(lineSegment)
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
            y: isRelative ? currentPoint.y - args[i + 1] : reflectY(args[i + 1], svgHeight),
          }
          const lineSegment: Line = [
            currentPoint,
            STRAIGHT_LINE_HANDLE,
            STRAIGHT_LINE_HANDLE,
            newPoint,
          ]
          currentSegments.push(lineSegment)
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
            y: currentPoint.y, // y stays the same for horizontal lines
          }
          const lineSegment: Line = [
            currentPoint,
            STRAIGHT_LINE_HANDLE,
            STRAIGHT_LINE_HANDLE,
            newPoint,
          ]
          currentSegments.push(lineSegment)
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
            x: currentPoint.x, // x stays the same for vertical lines
            y: isRelative ? currentPoint.y - y : reflectY(y, svgHeight),
          }
          const lineSegment: Line = [
            currentPoint,
            STRAIGHT_LINE_HANDLE,
            STRAIGHT_LINE_HANDLE,
            newPoint,
          ]
          currentSegments.push(lineSegment)
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
            y: isRelative ? currentPoint.y - args[i + 1] : reflectY(args[i + 1], svgHeight),
          }
          const cp2: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: isRelative ? currentPoint.y - args[i + 3] : reflectY(args[i + 3], svgHeight),
          }
          const endPoint: Point = {
            x: args[i + 4] + (isRelative ? currentPoint.x : 0),
            y: isRelative ? currentPoint.y - args[i + 5] : reflectY(args[i + 5], svgHeight),
          }

          const curveSegment: BezierCurve = [currentPoint, cp1, cp2, endPoint]
          currentSegments.push(curveSegment)
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
            y: isRelative ? currentPoint.y - args[i + 1] : reflectY(args[i + 1], svgHeight),
          }
          const endPoint: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: isRelative ? currentPoint.y - args[i + 3] : reflectY(args[i + 3], svgHeight),
          }

          const curveSegment: BezierCurve = [currentPoint, cp1, cp2, endPoint]
          currentSegments.push(curveSegment)
          currentPoint = endPoint
          lastControlPoint = cp2
        }
        break
      }

      case 'z': {
        // ClosePath - close current path and start a new one
        if (currentPoint.x !== pathStart.x || currentPoint.y !== pathStart.y) {
          const lineSegment: Line = [
            currentPoint,
            STRAIGHT_LINE_HANDLE,
            STRAIGHT_LINE_HANDLE,
            pathStart,
          ]
          currentSegments.push(lineSegment)
        }
        currentPoint = pathStart
        lastControlPoint = null

        // Finish the current path (this creates a new array)
        finishCurrentPath()
        break
      }

      // Note: Q, T, A commands not implemented yet (quadratic bezier and arc)
      default:
        console.warn(`SVG path command '${command}' not supported yet`)
        lastControlPoint = null
    }
  }

  // Finish any remaining path
  finishCurrentPath()

  return allPaths
}

export default function parsePathData(dAttribute: string, svgHeight: number): PathSegment[][] {
  const commands = getDataPathCommands(dAttribute)
  const pathData = commandsToSegments(commands, svgHeight)

  return pathData
}
