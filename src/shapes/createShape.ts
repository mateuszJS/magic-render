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
  paths: { points: { x: number; y: number }[] }[]
  fills: FillInfo[]
} {
  const result: { paths: { points: { x: number; y: number }[] }[]; fills: FillInfo[] } = {
    paths: [],
    fills: [],
  }

  // Handle Path items (most common)
  if (item instanceof paper.Path) {
    try {
      // Don't flatten - we want to preserve the original curve information
      const points = convertSegmentsToLogicFormat(item.segments, item.closed)
      result.paths.push({ points })

      // Extract resolved fill information
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
          result.fills.push({
            kind: 'linear',
            stops,
            gradient: g, // Paper.js gradient with absolute coordinates
          })
        } else {
          result.fills.push({
            kind: 'solid',
            color: parseColor(fc.toCSS(true)),
          })
        }
      }
    } catch {
      // Ignore items that can't be processed
    }
  }

  // Recursively process children (groups, etc.)
  if ('children' in item && item.children && item.children.length) {
    item.children.forEach((child) => {
      const childResult = extractPathsFromItem(child)
      result.paths.push(...childResult.paths)
      result.fills.push(...childResult.fills)
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

    if (imported) {
      const { paths, fills } = extractPathsFromItem(imported)
      if (paths.length > 0) {
        // Get absolute path points (no manual transform needed!)
        const pathPoints = paths.map((p) => p.points)
        const boundingBox = getBoundingBox(pathPoints)

        // Build shape properties
        let shapeFill: ShapeFill = { solid: [0, 0, 0, 1] }

        if (fills.length > 0) {
          const fill = fills[0]
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

        // Add shape to renderer with absolute coordinates
        const absolutePaths = pathPoints.map((path) => path.map((p) => ({ x: p.x, y: p.y })))
        console.log('absolutePaths', absolutePaths)
        console.log('serializedProps', serializedProps)
        Logic.addShape(0, absolutePaths, null, serializedProps, Textures.createSDF())
      }
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
