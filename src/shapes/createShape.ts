import paper from 'paper'
import * as Logic from 'logic/index.zig'
import * as Textures from 'textures'
import { getBoundingBox } from './boundingBox'
import convertFill, { FillInfo } from './convertFill'
import convertSegmentsToLogicFormat from './convertSegmentsToLogicFormat'

// Import the exact types from Logic module
type GradientStop = {
  color: [number, number, number, number]
  offset: number
}

type LinearGradient = {
  start: { x: number; y: number }
  end: { x: number; y: number }
  stops: GradientStop[]
}

type ShapeFill = { solid: [number, number, number, number] } | { linear: LinearGradient }

// Extract absolute geometry and fills from Paper.js items
function extractPathsFromItem(item: paper.Item): {
  paths: { points: { x: number; y: number }[]; fill: FillInfo | null }[]
  groups: {
    paths: { points: { x: number; y: number }[]; fill: FillInfo | null }[]
    groupFill: FillInfo | null
  }[]
} {
  const result: {
    paths: { points: { x: number; y: number }[]; fill: FillInfo | null }[]
    groups: {
      paths: { points: { x: number; y: number }[]; fill: FillInfo | null }[]
      groupFill: FillInfo | null
    }[]
  } = {
    paths: [],
    groups: [],
  }

  // Handle Path items (most common)
  if (item instanceof paper.Path) {
    try {
      // Don't flatten - we want to preserve the original curve information
      // Paper.js has already applied all transformations from parent groups
      const points = convertSegmentsToLogicFormat(item.segments, item.closed)

      result.paths.push({ points, fill: convertFill(item.fillColor) })
    } catch {
      // Ignore items that can't be processed
    }
  }
  // Handle Shape items (rectangles, circles, etc.)
  else if (item instanceof paper.Shape) {
    try {
      // Convert shape to path to get standardized point format
      const pathFromShape = item.toPath(false) // false = don't insert into project
      if (pathFromShape && pathFromShape.segments) {
        const points = convertSegmentsToLogicFormat(pathFromShape.segments, pathFromShape.closed)

        // Extract fill information from the original shape
        result.paths.push({ points, fill: convertFill(item.fillColor) })

        // Clean up the temporary path
        pathFromShape.remove()
      }
    } catch {
      // Ignore items that can't be processed
    }
  }
  // Handle Group items - treat as separate logical groups
  else if (item instanceof paper.Group) {
    console.log('Processing group:', item)

    // Collect all paths within this group
    const groupPaths: { points: { x: number; y: number }[]; fill: FillInfo | null }[] = []

    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      groupPaths.push(...childResult.paths)
      // Also collect any nested groups
      result.groups.push(...childResult.groups)
    })

    // Add this group as a separate entity
    if (groupPaths.length > 0) {
      result.groups.push({ paths: groupPaths, groupFill: convertFill(item.fillColor) })
    }
  }

  // Recursively process other children (layers, compound paths, etc.)
  if (
    'children' in item &&
    item.children &&
    item.children.length &&
    !(item instanceof paper.Group)
  ) {
    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      result.paths.push(...childResult.paths) // Each path stays separate
      result.groups.push(...childResult.groups)
    })
  }

  // Handle CompoundPath items (paths with holes)
  else if (item instanceof paper.CompoundPath) {
    console.log('Processing CompoundPath')
    item.children.forEach((child) => {
      if (child instanceof paper.Path) {
        const childResult = extractPathsFromItem(child)
        result.paths.push(...childResult.paths)
      }
    })
  }

  return result
}

export default function createShapes(svg: string): void {
  // Create Paper.js scope to process SVG
  const scope = new paper.PaperScope()
  scope.setup(new paper.Size(1024, 1024))
  const project = scope.project

  try {
    // Import SVG - Paper.js automatically resolves all transforms
    const imported = project.importSVG(svg)
    console.log('imported', imported)
    if (imported) {
      const { paths, groups } = extractPathsFromItem(imported)

      // Helper function to create a shape from path data
      const createShapeFromPaths = (
        pathsData: { points: { x: number; y: number }[]; fill: FillInfo | null }[],
        defaultFill: FillInfo | null
      ) => {
        pathsData.forEach((pathData) => {
          console.log('pathData', pathData)
          const pathPoints = [pathData.points]
          const boundingBox = getBoundingBox(pathPoints)

          // Build shape properties for this specific path
          let shapeFill: ShapeFill = { solid: [0, 0, 0, 1] }

          // Use path-specific fill, or fall back to group fill, or default
          const fillToUse = pathData.fill || defaultFill
          if (fillToUse) {
            const fill = fillToUse
            if (fill.kind === 'solid' && fill.color) {
              shapeFill = { solid: fill.color }
            } else if (
              fill.kind === 'linear' &&
              fill.stops &&
              fill.gradientStart &&
              fill.gradientEnd
            ) {
              // Use the extracted gradient coordinates from FillInfo
              const start = fill.gradientStart
              const end = fill.gradientEnd
              console.log('gradient start', start, 'and end', end)
              // Reflect gradient coordinates to match the reflected coordinate system
              const svgHeight = imported.bounds?.height || 0
              const reflectedStart = { x: start.x, y: svgHeight - start.y }
              const reflectedEnd = { x: end.x, y: svgHeight - end.y }

              // Normalize to bounding box space for shader
              const bbw = boundingBox.max_x - boundingBox.min_x || 1
              const bbh = boundingBox.max_y - boundingBox.min_y || 1
              const p1 = {
                x: (reflectedStart.x - boundingBox.min_x) / bbw,
                y: (reflectedStart.y - boundingBox.min_y) / bbh,
              }
              const p2 = {
                x: (reflectedEnd.x - boundingBox.min_x) / bbw,
                y: (reflectedEnd.y - boundingBox.min_y) / bbh,
              }
              console.log('Original gradient:', { start, end })
              console.log('Reflected gradient:', { reflectedStart, reflectedEnd })
              console.log('Normalized gradient:', { p1, p2 })
              shapeFill = { linear: { stops: fill.stops, start: p1, end: p2 } }
            }
          }

          const serializedProps = {
            fill: shapeFill,
            stroke: shapeFill, // Use same fill for stroke as fallback
            stroke_width: 0,
          }

          // Add each path as a separate shape
          const absolutePaths = pathPoints.map((path) => path.map((p) => ({ x: p.x, y: p.y })))

          // Reflect Y-axis: convert from SVG coordinates (top-left origin) to creator coordinates (bottom-left origin)
          const svgHeight = imported.bounds?.height // Use SVG height or fallback
          if (!svgHeight) {
            throw Error('SVG height is required')
          }
          const reflectedPaths = absolutePaths.map((path) =>
            path.map((p) => ({ x: p.x, y: svgHeight - p.y }))
          )

          // console.log('absolutePaths', absolutePaths)
          // console.log('reflectedPaths', reflectedPaths)
          console.log('serializedProps', serializedProps)
          Logic.addShape(0, reflectedPaths, null, serializedProps, Textures.createSDF())
        })
      }

      // Process individual paths (not in groups)
      if (paths.length > 0) {
        // console.log('Processing individual paths:', paths.length)
        createShapeFromPaths(paths, null)
      }

      // Process groups as separate logical entities
      groups.forEach((group, index) => {
        // console.log(`Processing group ${index}:`, group.paths.length, 'paths')
        createShapeFromPaths(group.paths, group.groupFill)
      })
    }
  } catch (error) {
    console.error('Error processing SVG with Paper.js:', error)
  } finally {
    // Cleanup Paper.js scope
    if (scope.project) {
      scope.project.clear()
    }
  }
}
