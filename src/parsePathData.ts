interface Point {
  x: number
  y: number
}

type Line = [Point, Point]
type BezierCurve = [Point, Point, Point, Point] // start, control1, control2, end

interface ParsedPath {
  lines: Line[][] // Array of paths, each path is an array of lines
  curves: BezierCurve[][] // Array of paths, each path is an array of curves
}

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

function commandsToSegments(commands: PathCommand[]): { lines: Line[][]; curves: BezierCurve[][] } {
  const allLines: Line[][] = []
  const allCurves: BezierCurve[][] = []

  let currentLines: Line[] = []
  let currentCurves: BezierCurve[] = []
  let currentPoint: Point = { x: 0, y: 0 }
  let pathStart: Point = { x: 0, y: 0 }
  let lastControlPoint: Point | null = null

  const finishCurrentPath = () => {
    if (currentLines.length > 0) {
      allLines.push([...currentLines])
      currentLines = []
    }
    if (currentCurves.length > 0) {
      allCurves.push([...currentCurves])
      currentCurves = []
    }
  }

  for (const { command, args } of commands) {
    switch (command.toLowerCase()) {
      case 'm': {
        // MoveTo - start a new sub-path if we have existing segments
        if (currentLines.length > 0 || currentCurves.length > 0) {
          finishCurrentPath()
        }

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
            currentLines.push([currentPoint, newPoint])
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
          currentLines.push([currentPoint, newPoint])
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
          currentLines.push([currentPoint, newPoint])
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
          currentLines.push([currentPoint, newPoint])
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

          currentCurves.push([currentPoint, cp1, cp2, endPoint])
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

          currentCurves.push([currentPoint, cp1, cp2, endPoint])
          currentPoint = endPoint
          lastControlPoint = cp2
        }
        break
      }

      case 'z': {
        // ClosePath - close current path and start a new one
        if (currentPoint.x !== pathStart.x || currentPoint.y !== pathStart.y) {
          currentLines.push([currentPoint, pathStart])
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

  return { lines: allLines, curves: allCurves }
}

export default function parsePathData(dAttribute: string): ParsedPath {
  const commands = getDataPathCommands(dAttribute)
  const pathData = commandsToSegments(commands)

  return {
    lines: pathData.lines,
    curves: pathData.curves,
  }
}
