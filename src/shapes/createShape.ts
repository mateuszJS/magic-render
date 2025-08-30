import paper from 'paper'
import { Node } from 'svg-parser'
import * as Logic from 'logic/index.zig'
import parseColor from './parseColor'
import * as Textures from 'textures'
import { getBoundingBox } from './boundingBox'
import { STRAIGHT_LINE_HANDLE } from './const'

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

// Convert svg-parser node tree back to SVG string for Paper.js import
function nodeToSvg(node: Node | string): string {
  if (typeof node === 'string') return node
  // svg-parser types are incomplete, use unknown for safety
  const element = node as unknown as {
    tagName?: string
    properties?: Record<string, unknown>
    children?: (Node | string)[]
  }
  const tag = element.tagName || 'g'
  const props = element.properties || {}
  const attrs = Object.keys(props)
    .map((k) => `${k}="${String(props[k]).replace(/"/g, '&quot;')}"`)
    .join(' ')
  const children = (element.children || []).map(nodeToSvg).join('')
  return `<${tag} ${attrs}>${children}</${tag}>`
}

interface FillInfo {
  kind: 'solid' | 'linear'
  color?: [number, number, number, number]
  stops?: GradientStop[]
  gradient?: unknown // Paper.js gradient types are complex
}

// Convert Paper.js path segments to Logic module format
function convertSegmentsToLogicFormat(
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

// Extract absolute geometry and fills from Paper.js items
function extractPathsFromItem(item: paper.Item): {
  paths: { points: { x: number; y: number }[]; fill?: FillInfo }[]
  groups: {
    paths: { points: { x: number; y: number }[]; fill?: FillInfo }[]
    groupFill?: FillInfo
  }[]
} {
  const result: {
    paths: { points: { x: number; y: number }[]; fill?: FillInfo }[]
    groups: {
      paths: { points: { x: number; y: number }[]; fill?: FillInfo }[]
      groupFill?: FillInfo
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
      console.log('item', item)
      const points = convertSegmentsToLogicFormat(item.segments, item.closed)

      // Extract resolved fill information for this specific path
      let fillInfo: FillInfo | undefined
      const fc = item.fillColor
      if (fc) {
        // Check if this is a gradient fill (Paper.js internal structure)
        const gradientFc = fc as unknown as {
          gradient?: {
            stops: { rampPoint: number; color: { toCSS: (includeAlpha: boolean) => string } }[]
            origin?: { x: number; y: number }
            destination?: { x: number; y: number }
          }
        }
        if (gradientFc.gradient) {
          const g = gradientFc.gradient
          const stops: GradientStop[] = g.stops.map((s) => ({
            offset: s.rampPoint,
            color: parseColor(s.color.toCSS(true)),
          }))
          fillInfo = {
            kind: 'linear',
            stops,
            gradient: g, // Paper.js gradient with absolute coordinates
          }
        } else {
          fillInfo = {
            kind: 'solid',
            color: parseColor(fc.toCSS(true)),
          }
        }
      }

      result.paths.push({ points, fill: fillInfo })
    } catch {
      // Ignore items that can't be processed
    }
  }
  // Handle Shape items (rectangles, circles, etc.)
  else if (item instanceof paper.Shape) {
    try {
      console.log('Processing Shape:', item.type)
      
      // Convert shape to path to get standardized point format
      const pathFromShape = item.toPath(false) // false = don't insert into project
      if (pathFromShape && pathFromShape.segments) {
        const points = convertSegmentsToLogicFormat(pathFromShape.segments, pathFromShape.closed)

        // Extract fill information from the original shape
        let fillInfo: FillInfo | undefined
        const fc = item.fillColor
        if (fc) {
          const gradientFc = fc as unknown as {
            gradient?: {
              stops: { rampPoint: number; color: { toCSS: (includeAlpha: boolean) => string } }[]
              origin?: { x: number; y: number }
              destination?: { x: number; y: number }
            }
          }
          if (gradientFc.gradient) {
            const g = gradientFc.gradient
            const stops: GradientStop[] = g.stops.map((s) => ({
              offset: s.rampPoint,
              color: parseColor(s.color.toCSS(true)),
            }))
            fillInfo = {
              kind: 'linear',
              stops,
              gradient: g,
            }
          } else {
            fillInfo = {
              kind: 'solid',
              color: parseColor(fc.toCSS(true)),
            }
          }
        }

        result.paths.push({ points, fill: fillInfo })
        
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

    // Extract group-level fill if any
    let groupFillInfo: FillInfo | undefined
    const groupFc = item.fillColor
    if (groupFc) {
      const gradientFc = groupFc as unknown as {
        gradient?: {
          stops: { rampPoint: number; color: { toCSS: (includeAlpha: boolean) => string } }[]
          origin?: { x: number; y: number }
          destination?: { x: number; y: number }
        }
      }
      if (gradientFc.gradient) {
        const g = gradientFc.gradient
        const stops: GradientStop[] = g.stops.map((s) => ({
          offset: s.rampPoint,
          color: parseColor(s.color.toCSS(true)),
        }))
        groupFillInfo = {
          kind: 'linear',
          stops,
          gradient: g,
        }
      } else {
        groupFillInfo = {
          kind: 'solid',
          color: parseColor(groupFc.toCSS(true)),
        }
      }
    }

    // Collect all paths within this group
    const groupPaths: { points: { x: number; y: number }[]; fill?: FillInfo }[] = []

    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      groupPaths.push(...childResult.paths)
      // Also collect any nested groups
      result.groups.push(...childResult.groups)
    })

    // Add this group as a separate entity
    if (groupPaths.length > 0) {
      result.groups.push({ paths: groupPaths, groupFill: groupFillInfo })
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

export default function createShapes(node: Node): void {
  // Convert parsed SVG node back to SVG string
  const svgFragment = nodeToSvg(node)
  const svg = svgFragment.trim().startsWith('<svg')
    ? svgFragment
    : `<svg xmlns="http://www.w3.org/2000/svg">${svgFragment}</svg>`

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
        pathsData: { points: { x: number; y: number }[]; fill?: FillInfo }[],
        defaultFill?: FillInfo
      ) => {
        pathsData.forEach((pathData) => {
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
            } else if (fill.kind === 'linear' && fill.stops && fill.gradient) {
              // Paper.js gradient has absolute start/end coordinates!
              const g = fill.gradient as {
                origin?: { x: number; y: number }
                destination?: { x: number; y: number }
              }
              const start = { x: g.origin?.x || 0, y: g.origin?.y || 0 }
              const end = { x: g.destination?.x || 1, y: g.destination?.y || 0 }

              // Normalize to bounding box space for shader
              const bbw = boundingBox.max_x - boundingBox.min_x || 1
              const bbh = boundingBox.max_y - boundingBox.min_y || 1
              const p1 = {
                x: (start.x - boundingBox.min_x) / bbw,
                y: (start.y - boundingBox.min_y) / bbh,
              }
              const p2 = {
                x: (end.x - boundingBox.min_x) / bbw,
                y: (end.y - boundingBox.min_y) / bbh,
              }

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

          console.log('absolutePaths', absolutePaths)
          console.log('reflectedPaths', reflectedPaths)
          console.log('serializedProps', serializedProps)
          Logic.addShape(0, reflectedPaths, null, serializedProps, Textures.createSDF())
        })
      }

      // Process individual paths (not in groups)
      if (paths.length > 0) {
        console.log('Processing individual paths:', paths.length)
        createShapeFromPaths(paths)
      }

      // Process groups as separate logical entities
      groups.forEach((group, index) => {
        console.log(`Processing group ${index}:`, group.paths.length, 'paths')
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
