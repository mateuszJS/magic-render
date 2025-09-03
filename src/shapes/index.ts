import { Node } from 'svg-parser'
import * as Logic from 'logic/index.zig'
import parseRect from './parseRect'
import parseEllipse from './parseEllipse'
import * as Textures from 'textures'
import { BoundingBox, getBoundingBox } from './boundingBox'
import {
  ensureNumber,
  getProps,
  IDENTITY_MATRIX,
  isStraightHandle,
  parseColor,
  parseTransform,
} from './utils'
import * as radialGradient from './radialGradient'
import { Def, Defs } from './definitions'

function applyLinearTransform(x: number, y: number, m: number[]): Point {
  const [a, b, c, d, e, f] = m
  return {
    x: a * x + c * y + e,
    y: b * x + d * y + f,
  }
}

// Convert stops (apply opacity) and bake transform. Here we assume gradientUnits=userSpaceOnUse.
function toRuntimeGradient(def: Def, boundingBox: BoundingBox): ShapeProps['fill'] | null {
  if (def.type !== 'linear-gradient' && def.type !== 'radial-gradient') {
    console.error('toRuntimeGradient receive definition which is not a gradient!')
    return null
  }

  if (!def.stops) {
    console.error('Gradient without stops!', def)
    return null
  }

  // gradient with matrix are treated as absolute in svg, position doesn't depend on shape(owner)
  const tf = def.gradientTransform || IDENTITY_MATRIX

  if (def.type === 'linear-gradient') {
    const x1_rel = ensureNumber(def.x1)
    const y1_rel = ensureNumber(def.y1)
    const x2_rel = ensureNumber(def.x2)
    const y2_rel = ensureNumber(def.y2)

    // if (def.gradientUnits === 'objectBoundingBox') {
    const p1 = applyLinearTransform(x1_rel, y1_rel, tf)
    const p2 = applyLinearTransform(x2_rel, y2_rel, tf)
    // at this point p and p2 ARE CORRECT but for absolute value, according to whole svg boudning box(not just shape)

    const bbWidth = boundingBox.max_x - boundingBox.min_x
    const bbHeight = boundingBox.max_y - boundingBox.min_y

    p1.x = (p1.x - boundingBox.min_x) / bbWidth
    p1.y = 1 - (p1.y - boundingBox.min_y) / bbHeight
    p2.x = (p2.x - boundingBox.min_x) / bbWidth
    p2.y = 1 - (p2.y - boundingBox.min_y) / bbHeight

    return { linear: { stops: def.stops, start: p1, end: p2 } }
  } else if (def.type === 'radial-gradient') {
    const cx = ensureNumber(def.cx, 0.5)
    const cy = ensureNumber(def.cy, 0.5)
    const r = ensureNumber(def.r, 0.5)

    const bbWidth = boundingBox.max_x - boundingBox.min_x
    const bbHeight = boundingBox.max_y - boundingBox.min_y

    const cAbs = applyLinearTransform(cx, cy, tf)
    const exAbs = applyLinearTransform(cx + r, cy, tf) // +X
    const eyAbs = applyLinearTransform(cx, cy + r, tf) // +Y

    // Normalize positions
    const toNorm = (p: Point): Point => ({
      x: (p.x - boundingBox.min_x) / Math.max(bbWidth, 1e-8),
      y: 1 - (p.y - boundingBox.min_y) / Math.max(bbHeight, 1e-8),
    })
    const center = toNorm(cAbs)
    const ex = toNorm(exAbs)
    const ey = toNorm(eyAbs)

    const vx = { x: ex.x - center.x, y: ex.y - center.y }
    const vy = { x: ey.x - center.x, y: ey.y - center.y }
    const { destination, ratio } = radialGradient.getCorrectDestinationRatio(center, vx, vy)

    return {
      radial: {
        stops: def.stops,
        center,
        destination,
        radius_ratio: ratio,
      },
    }
  }
  return null
}

export function createShapes(
  node: Node,
  defs: Defs,
  svgWidth: number,
  svgHeight: number,
  parentTransform: number[] = IDENTITY_MATRIX
): void {
  if (!('children' in node)) return

  node.children.forEach((child) => {
    if (typeof child === 'string') return

    let currTransform = parentTransform

    if ('properties' in child && typeof child.properties === 'object') {
      let props = getProps(child)
      let paths: Point[][] | undefined = props.paths

      switch (child.tagName) {
        case 'rect': {
          if (typeof props?.width !== 'number' || typeof props?.height !== 'number') {
            throw Error("Rect without 'width' or 'height' property")
          }
          const x = typeof props.x === 'number' ? props.x : 0
          const y = typeof props.y === 'number' ? props.y : 0

          paths = [parseRect(x, y, props.width, props.height)]
          break
        }
        case 'ellipse': {
          if (typeof props?.rx !== 'number' || typeof props?.ry !== 'number') {
            throw Error("Ellipse without 'rx' or 'ry' property")
          }
          if (typeof props?.cx !== 'number' || typeof props?.cy !== 'number') {
            throw Error("Ellipse without 'cx' or 'cy' property")
          }
          paths = [parseEllipse(props.cx, props.cy, props.rx, props.ry)]
          break
        }
        case 'circle': {
          if (typeof props?.r !== 'number') {
            throw Error("Circle without 'r' property")
          }
          if (typeof props?.cx !== 'number' || typeof props?.cy !== 'number') {
            throw Error("Circle without 'cx' or 'cy' property")
          }
          paths = [parseEllipse(props.cx, props.cy, props.r, props.r)]
          break
        }
        case 'g': {
          currTransform = parseTransform(props.transform as string | undefined, currTransform)
          break
        }
        case 'defs': {
          return // do not render any content of defs, those were collected already
        }
        case 'use': {
          if (props.href) {
            const id = (props.href as string).slice(1)
            if (id) {
              const def = defs[id]
              if (def) {
                if (!def.paths) {
                  throw Error('The resolved definition of <use> has no paths!')
                }

                paths = def.paths
                props = {
                  ...def,
                  ...props,
                }
              }
            }
          }
          break
        }
      }

      if (paths) {
        const boundingBox = getBoundingBox(paths)

        const serializedProps: Partial<ShapeProps> = {
          fill: { solid: [0, 0, 0, 1] },
          stroke: { solid: [0, 0, 0, 1] },
          stroke_width: 0,
        }
        // fill/stroke: color or url(#id)
        if (props.fill) {
          const fill = String(props.fill)
          const m = fill.match(/^url\(#([^)]+)\)$/)

          if (m) {
            const def = defs[m[1]]
            if (def) {
              // if (props.id === 'eyelid_left') debugger
              const grad = toRuntimeGradient(def, boundingBox)
              if (grad) serializedProps.fill = grad
            }
          } else {
            const rgba = parseColor(fill)
            serializedProps.fill = { solid: rgba }
          }
        }
        if (props.stroke) {
          const stroke = String(props.stroke)
          const m = stroke.match(/^url\(#([^)]+)\)$/)
          if (m) {
            const def = defs[m[1]]
            if (def) {
              const grad = toRuntimeGradient(def, boundingBox)
              if (grad) serializedProps.stroke = grad
            }
          } else {
            const rgba = parseColor(stroke)
            serializedProps.stroke = { solid: rgba }
          }
        }

        if (typeof props.transform === 'string') {
          currTransform = parseTransform(props.transform, currTransform)
        }
        const transformedPaths = paths.map((path) =>
          path.map((point) => {
            if (isStraightHandle(point)) return point
            return applyLinearTransform(point.x, point.y, currTransform)
          })
        )

        const correctedPaths = transformedPaths.map((path) =>
          path.map((p) => ({ x: p.x, y: svgHeight - p.y }))
        )
        Logic.addShape(0, correctedPaths, null, serializedProps, Textures.createSDF())
      }
    }
    createShapes(child, defs, svgWidth, svgHeight, currTransform)
  })
}
