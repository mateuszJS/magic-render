import { Node } from 'svg-parser'
import { BoundingBox, getBoundingBox } from './boundingBox'
import {
  getNum,
  IDENTITY_MATRIX,
  isElementNode,
  isStraightHandle,
  parseColor,
  parseTransform,
} from './utils'
import * as radialGradient from './radialGradient'
import { Def, Defs, DefStop } from './definitions'
import getProps from './getProps'

export interface ShapeData {
  paths: Point[][]
  props: ShapeProps
  boundingBox: BoundingBox
}

function applyLinearTransform(x: number, y: number, m: number[]): Point {
  const [a, b, c, d, e, f] = m
  return {
    x: a * x + c * y + e,
    y: b * x + d * y + f,
  }
}

// Convert stops (apply opacity) and bake transform. Here we assume gradientUnits=userSpaceOnUse.
function toRuntimeGradient(
  def: Def,
  boundingBox: BoundingBox,
  overrideAlpha = 1
): SdfEffect['fill'] | null {
  if (def.type !== 'linear-gradient' && def.type !== 'radial-gradient') {
    console.error('toRuntimeGradient receive definition which is not a gradient!')
    return null
  }

  if (!def.stops) {
    console.error('Gradient without stops!', def)
    return null
  }

  const stops = def.stops.map<DefStop>((stop) => ({
    ...stop,
    color: [
      stop.color[0] * overrideAlpha,
      stop.color[1] * overrideAlpha,
      stop.color[2] * overrideAlpha,
      stop.color[3] * overrideAlpha,
    ],
  }))

  // gradient with matrix are treated as absolute in svg, position doesn't depend on shape(owner)
  const tf = def.gradientTransform || IDENTITY_MATRIX

  if (def.type === 'linear-gradient') {
    const x1_rel = getNum(def.x1)
    const y1_rel = getNum(def.y1)
    const x2_rel = getNum(def.x2)
    const y2_rel = getNum(def.y2)

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

    return { linear: { stops, start: p1, end: p2 } }
  } else if (def.type === 'radial-gradient') {
    const cx = getNum(def.cx, 0.5)
    const cy = getNum(def.cy, 0.5)
    const r = getNum(def.r, 0.5)

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
        stops,
        center,
        destination,
        radius_ratio: ratio,
      },
    }
  }
  return null
}

export default function collectShapesData(
  node: Node | string,
  defs: Defs,
  parentTransform: number[] = IDENTITY_MATRIX,
  uiElementType?: UiElementType
): ShapeData[] {
  const shapes: ShapeData[] = []

  if (!isElementNode(node)) return shapes

  let currTransform = parentTransform

  if ('properties' in node && typeof node.properties === 'object') {
    let props = getProps(node)
    let paths: Point[][] | undefined = props.paths

    switch (node.tagName) {
      case 'g': {
        currTransform = parseTransform(props.transform as string | undefined, currTransform)
        break
      }
      case 'defs': {
        return shapes // do not render content of defs, those are collected prior to this function run
      }
      case 'use': {
        if (props.href) {
          const id = (props.href as string).slice(1)
          if (id) {
            const def = defs[id]
            if (def) {
              if (!def.paths) {
                console.error('The resolved definition of <use> has no paths!')
                return shapes
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

      const serializedProps: ShapeProps = {
        sdf_effects: [],
        filter: null,
        opacity: 1,
      }
      // fill/stroke: color or url(#id)
      if (props.fill) {
        const fillOpacity = getNum(props['fill-opacity'], 1)
        const fill = String(props.fill)
        const m = fill.match(/^url\(#([^)]+)\)$/)
        let serializedFill: SdfEffect['fill'] | null = null

        if (m) {
          const def = defs[m[1]]
          if (def) {
            const grad = toRuntimeGradient(def, boundingBox, fillOpacity)
            if (grad) {
              serializedFill = grad
            }
          }
        } else {
          const rgba = parseColor(fill, fillOpacity)
          serializedFill = { solid: rgba }
        }

        if (serializedFill) {
          serializedProps.sdf_effects.push({
            dist_start: Number.MAX_SAFE_INTEGER,
            dist_end: 0,
            fill: serializedFill,
          })
        }
      }

      if (props['stroke-width']) {
        const color = String(props.stroke) || '#000'
        const width = getNum(props['stroke-width'], 1)
        const m = color.match(/^url\(#([^)]+)\)$/)
        let serializedFill: SdfEffect['fill'] | null = null

        if (m) {
          const def = defs[m[1]]
          if (def) {
            const grad = toRuntimeGradient(def, boundingBox)
            if (grad) {
              serializedFill = grad
            }
          }
        } else {
          const rgba = parseColor(color)
          serializedFill = { solid: rgba }
        }

        if (serializedFill) {
          serializedProps.sdf_effects.push({
            dist_start: width / 2,
            dist_end: -width / 2,
            fill: serializedFill,
          })
        }
      }

      if (props.filter) {
        const filter = String(props.filter)
        const m = filter.match(/^url\(#([^)]+)\)$/)

        if (m) {
          const def = defs[m[1]]
          if (def?.stdDeviation) {
            serializedProps.filter = {
              gaussianBlur: {
                x: def.stdDeviation[0],
                y: def.stdDeviation[1],
              },
            }
          }
        }
      }

      if (typeof props.opacity === 'number') {
        serializedProps.opacity = props.opacity
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

      shapes.push({
        paths: transformedPaths,
        props: serializedProps,
        boundingBox,
      })
    }
  }

  node.children.forEach((child) => {
    shapes.push(...collectShapesData(child, defs, currTransform, uiElementType))
  })

  return shapes
}
