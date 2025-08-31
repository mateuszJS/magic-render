import paper from 'paper'
import * as Logic from 'logic/index.zig'
import * as Textures from 'textures'
import { getBoundingBox } from './boundingBox'
import convertFill from './convertFill'
import convertSegmentsToLogicFormat from './convertSegmentsToLogicFormat'
import reflectGradientStops from './reflectGradientStop'

type ShapeFill =
  | { linear: LinearGradient }
  | { radial: RadialGradient }
  | { solid: [number, number, number, number] }

type PathFill = {
  points: Point[]
  fill: ShapeFill | null
}
type GroupFill = {
  paths: PathFill[]
  groupFill: ShapeFill | null
}
// Extract absolute geometry and fills from Paper.js items
function extractPathsFromItem(item: paper.Item): {
  paths: PathFill[]
  groups: GroupFill[]
} {
  const paths: PathFill[] = []
  const groups: GroupFill[] = []

  // Handle Path items (most common)
  if (item instanceof paper.Path) {
    const points = convertSegmentsToLogicFormat(item.segments, item.closed)
    paths.push({ points, fill: convertFill(item.fillColor) })
  } else if (item instanceof paper.Shape) {
    // (rectangles, circles, etc.)
    const pathFromShape = item.toPath(false)
    if (pathFromShape.segments) {
      const points = convertSegmentsToLogicFormat(pathFromShape.segments, pathFromShape.closed)

      // Extract fill information from the original shape
      paths.push({ points, fill: convertFill(item.fillColor) })

      // Clean up the temporary path
      pathFromShape.remove()
    }
  } else if (item instanceof paper.Group) {
    // Collect all paths within this group
    const groupPaths: PathFill[] = []

    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      groupPaths.push(...childResult.paths)
      // Also collect any nested groups
      groups.push(...childResult.groups)
    })

    // Add this group as a separate entity
    if (groupPaths.length > 0) {
      groups.push({ paths: groupPaths, groupFill: convertFill(item.fillColor) })
    }
  }

  // Recursively process other children (layers, compound paths, etc.)
  if (
    'children' in item && // paper.js typescript definitions are not up to date
    item.children && // children might not exist
    item.children.length &&
    !(item instanceof paper.Group)
  ) {
    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      paths.push(...childResult.paths) // Each path stays separate
      groups.push(...childResult.groups)
    })
  } else if (item instanceof paper.CompoundPath) {
    // Handle CompoundPath items (paths with holes)
    item.children.forEach((child) => {
      if (child instanceof paper.Path) {
        const childResult = extractPathsFromItem(child)
        paths.push(...childResult.paths)
      }
    })
  }

  return { paths, groups }
}

export default function createShapes(svg: string): void {
  // Create Paper.js scope to process SVG
  const scope = new paper.PaperScope()
  scope.setup(new paper.Size(1024, 1024))
  const project = scope.project

  try {
    // Import SVG - Paper.js automatically resolves all transforms
    const imported = project.importSVG(svg)

    if (imported) {
      const { paths, groups } = extractPathsFromItem(imported)

      // Helper function to create a shape from path data
      const createShapeFromPaths = (pathsData: PathFill[], defaultFill: ShapeFill | null) => {
        pathsData.forEach((pathData) => {
          const pathPoints = [pathData.points]
          const boundingBox = getBoundingBox(pathPoints)

          // Use path-specific fill, or fall back to group fill, or default
          const shapeFill = pathData.fill || defaultFill
          if (shapeFill && 'linear' in shapeFill) {
            // Reflect gradient coordinates to match the reflected coordinate system
            const { start, end } = reflectGradientStops(
              imported.bounds.height,
              shapeFill.linear.start,
              shapeFill.linear.end,
              boundingBox
            )
            shapeFill.linear.start = start
            shapeFill.linear.end = end
          } else if (shapeFill && 'radial' in shapeFill) {
            // For radial gradients, reflect the center point
            const { start, end } = reflectGradientStops(
              imported.bounds.height,
              shapeFill.radial.center,
              shapeFill.radial.radius,
              boundingBox
            )

            shapeFill.radial.center = start
            shapeFill.radial.radius = end
          }

          const serializedProps = {
            fill: shapeFill || undefined || { solid: [1, 0, 1, 1] }, // Use same fill for fill as fallback
            stroke: shapeFill || undefined || { solid: [1, 0, 1, 1] }, // Use same fill for fill as fallback // Use same fill for stroke as fallback
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

          console.log('serializedProps', serializedProps)
          Logic.addShape(0, reflectedPaths, null, serializedProps, Textures.createSDF())
        })
      }

      // Process individual paths (not in groups)
      if (paths.length > 0) {
        createShapeFromPaths(paths, null)
      }

      // Process groups as separate logical entities
      groups.forEach((group) => {
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
