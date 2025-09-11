import arcToBezier from './arcToBezier'
import { STRAIGHT_LINE_HANDLE } from './const'

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

function commandsToPoints(commands: PathCommand[]): Point[][] {
  const allShapes: Point[][] = []

  let currentPoints: Point[] = []
  let currentPoint: Point = { x: 0, y: 0 }
  let pathStart: Point = { x: 0, y: 0 }
  let lastHandle: Point | null = null

  const finishCurrentPath = () => {
    if (currentPoints.length > 0) {
      allShapes.push([...currentPoints])
      currentPoints = []
    }
  }

  for (const { command, args } of commands) {
    switch (command.toLowerCase()) {
      case 'm': {
        // MoveTo - start a new sub-path
        finishCurrentPath()

        const isRelative = command === 'm'
        for (let i = 0; i < args.length; i += 2) {
          const newPoint = {
            x: isRelative ? currentPoint.x + args[i] : args[i],
            // Use SVG coordinates directly (no Y flip). For relative commands we add deltas.
            y: isRelative ? currentPoint.y + args[i + 1] : args[i + 1],
          }
          if (i === 0) {
            // First move is the start of a new path
            currentPoints.push(newPoint)
            pathStart = { ...newPoint }
          } else {
            // Subsequent moves are treated as LineTo
            currentPoints.push(STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, newPoint)
          }
          currentPoint = newPoint
        }
        lastHandle = null
        break
      }

      case 'l':
      case 'h':
      case 'v': {
        const isRelative = command !== command.toUpperCase()
        const isHorizontal = command.toLowerCase() === 'h'
        const isVertical = command.toLowerCase() === 'v'

        let argIndex = 0
        while (argIndex < args.length) {
          let newX = currentPoint.x
          let newY = currentPoint.y

          if (isHorizontal) {
            newX = args[argIndex] + (isRelative ? currentPoint.x : 0)
            argIndex += 1
          } else if (isVertical) {
            newY = args[argIndex] + (isRelative ? currentPoint.y : 0)
            argIndex += 1
          } else {
            newX = args[argIndex] + (isRelative ? currentPoint.x : 0)
            newY = args[argIndex + 1] + (isRelative ? currentPoint.y : 0)
            argIndex += 2
          }

          const newPoint = { x: newX, y: newY }
          currentPoints.push(STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, newPoint)
          currentPoint = newPoint
        }
        lastHandle = null
        break
      }

      case 'a': {
        // Arc
        const isRelative = command === 'a'
        for (let i = 0; i < args.length; i += 7) {
          const rx = args[i]
          const ry = args[i + 1]
          const xAxisRotation = args[i + 2]
          const largeArcFlag = args[i + 3]
          const sweepFlag = args[i + 4]
          const endPoint: Point = {
            x: args[i + 5] + (isRelative ? currentPoint.x : 0),
            y: args[i + 6] + (isRelative ? currentPoint.y : 0),
          }

          const curves = arcToBezier(
            currentPoint.x,
            currentPoint.y,
            rx,
            ry,
            xAxisRotation,
            largeArcFlag,
            sweepFlag,
            endPoint.x,
            endPoint.y
          )

          if (curves.length === 0) {
            // Degenerate arc → straight line to endPoint (if non-zero length)
            if (endPoint.x !== currentPoint.x || endPoint.y !== currentPoint.y) {
              currentPoints.push(STRAIGHT_LINE_HANDLE, STRAIGHT_LINE_HANDLE, endPoint)
            }
            currentPoint = endPoint
            lastHandle = null
          } else {
            for (const curve of curves) {
              currentPoints.push(
                { x: curve.cp1x, y: curve.cp1y },
                { x: curve.cp2x, y: curve.cp2y },
                { x: curve.x, y: curve.y }
              )
              currentPoint = { x: curve.x, y: curve.y }
            }
            // Arcs do not establish reflection for the next 'S/s' segment
            lastHandle = null
          }
        }
        break
      }

      case 'q': {
        // Quadratic Bezier
        const isRelative = command === 'q'
        for (let i = 0; i < args.length; i += 4) {
          const controlPoint: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const endPoint: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: args[i + 3] + (isRelative ? currentPoint.y : 0),
          }

          // Convert quadratic to cubic bezier
          // Cubic control points are at 1/3 and 2/3 along the quadratic control lines
          const h1: Point = {
            x: currentPoint.x + (2 / 3) * (controlPoint.x - currentPoint.x),
            y: currentPoint.y + (2 / 3) * (controlPoint.y - currentPoint.y),
          }
          const h2: Point = {
            x: endPoint.x + (2 / 3) * (controlPoint.x - endPoint.x),
            y: endPoint.y + (2 / 3) * (controlPoint.y - endPoint.y),
          }

          currentPoints.push(h1, h2, endPoint)
          currentPoint = endPoint
          lastHandle = controlPoint // Store quadratic control point for T command
        }
        break
      }

      case 't': {
        // Smooth Quadratic Bezier
        const isRelative = command === 't'
        for (let i = 0; i < args.length; i += 2) {
          // Reflect the previous quadratic control point
          const controlPoint: Point = lastHandle
            ? {
                x: 2 * currentPoint.x - lastHandle.x,
                y: 2 * currentPoint.y - lastHandle.y,
              }
            : { ...currentPoint }

          const endPoint: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }

          // Convert quadratic to cubic bezier
          const h1: Point = {
            x: currentPoint.x + (2 / 3) * (controlPoint.x - currentPoint.x),
            y: currentPoint.y + (2 / 3) * (controlPoint.y - currentPoint.y),
          }
          const h2: Point = {
            x: endPoint.x + (2 / 3) * (controlPoint.x - endPoint.x),
            y: endPoint.y + (2 / 3) * (controlPoint.y - endPoint.y),
          }

          currentPoints.push(h1, h2, endPoint)
          currentPoint = endPoint
          lastHandle = controlPoint
        }
        break
      }

      case 'c': {
        // Cubic Bezier
        const isRelative = command === 'c'
        for (let i = 0; i < args.length; i += 6) {
          const h1: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const h2: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: args[i + 3] + (isRelative ? currentPoint.y : 0),
          }
          const endPoint: Point = {
            x: args[i + 4] + (isRelative ? currentPoint.x : 0),
            y: args[i + 5] + (isRelative ? currentPoint.y : 0),
          }

          currentPoints.push(h1, h2, endPoint)
          currentPoint = endPoint
          lastHandle = h2
        }
        break
      }

      case 's': {
        // Smooth Cubic Bezier
        const isRelative = command === 's'
        for (let i = 0; i < args.length; i += 4) {
          const h1: Point = lastHandle
            ? {
                x: 2 * currentPoint.x - lastHandle.x,
                y: 2 * currentPoint.y - lastHandle.y,
              }
            : { ...currentPoint }

          const h2: Point = {
            x: args[i] + (isRelative ? currentPoint.x : 0),
            y: args[i + 1] + (isRelative ? currentPoint.y : 0),
          }
          const endPoint: Point = {
            x: args[i + 2] + (isRelative ? currentPoint.x : 0),
            y: args[i + 3] + (isRelative ? currentPoint.y : 0),
          }

          currentPoints.push(h1, h2, endPoint)
          currentPoint = endPoint
          lastHandle = h2
        }
        break
      }

      case 'z': {
        currentPoint = pathStart
        lastHandle = null
        finishCurrentPath()
        break
      }

      default:
        console.warn(`SVG path command '${command}' not supported yet`)
        lastHandle = null
    }
  }

  finishCurrentPath()

  return allShapes
}

export default function parsePathData(dAttribute: string): Point[][] {
  const commands = getDataPathCommands(dAttribute)
  const pathData = commandsToPoints(commands)

  return pathData
}
