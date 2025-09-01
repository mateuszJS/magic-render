import { STRAIGHT_LINE_HANDLE } from './const'

interface PathCommand {
  command: string
  args: number[]
}

export interface ShapeData {
  points: Point[]
  closed: boolean
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

function commandsToPoints(commands: PathCommand[]): ShapeData[] {
  const allShapes: ShapeData[] = []

  let currentPoints: Point[] = []
  let currentPoint: Point = { x: 0, y: 0 }
  let pathStart: Point = { x: 0, y: 0 }
  let lastHandle: Point | null = null
  let currentShapeClosed = false

  const finishCurrentPath = () => {
    if (currentPoints.length > 0) {
      allShapes.push({
        points: [...currentPoints],
        closed: currentShapeClosed,
      })
      currentPoints = []
      currentShapeClosed = false
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
        if (currentPoints.length > 0) {
          currentShapeClosed = true
        }
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

export default function parsePathData(dAttribute: string): ShapeData[] {
  const commands = getDataPathCommands(dAttribute)
  const pathData = commandsToPoints(commands)

  return pathData
}
