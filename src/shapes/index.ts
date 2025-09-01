import { Node, ElementNode } from 'svg-parser'
import * as Logic from 'logic/index.zig'
import parsePathData from './parsePathData'
import parseRect from './parseRect'
import parseColor from './parseColor'
import parseEllipse from './parseEllipse'
import * as Textures from 'textures'
import { getBoundingBox } from './boundingBox'

// Internal collection for raw defs from <defs>
type DefStop = { offset: number; color: [number, number, number, number]; opacity: number }
type LinearDef = {
  kind: 'linear'
  id: string
  x1?: number
  y1?: number
  x2?: number
  y2?: number
  gradientUnits?: 'objectBoundingBox' | 'userSpaceOnUse'
  gradientTransform?: string
  href?: string
  stops: DefStop[]
}
type RadialDef = {
  kind: 'radial'
  id: string
  cx?: number
  cy?: number
  r?: number
  fx?: number
  fy?: number
  gradientUnits?: 'objectBoundingBox' | 'userSpaceOnUse'
  gradientTransform?: string
  href?: string
  stops: DefStop[]
}
type AnyDef = LinearDef | RadialDef
export type Defs = Record<string, AnyDef>

const IDENTITY_MATRIX = [1, 0, 0, 1, 0, 0]

function multiplyMatrices(m1: number[], m2: number[]): number[] {
  const [a1, b1, c1, d1, e1, f1] = m1
  const [a2, b2, c2, d2, e2, f2] = m2
  return [
    a1 * a2 + c1 * b2,
    b1 * a2 + d1 * b2,
    a1 * c2 + c1 * d2,
    b1 * c2 + d1 * d2,
    a1 * e2 + c1 * f2 + e1,
    b1 * e2 + d1 * f2 + f1,
  ]
}

// Parse a gradientTransform into a single transformation matrix.
function parseTransform(
  str: string | undefined,
  initialMatrix: number[] = IDENTITY_MATRIX
): number[] {
  if (!str) return initialMatrix

  const regex = /(\w+)\(([^)]+)\)/g
  let match
  let currentMatrix = initialMatrix

  // We need to parse all operations first, then apply them right-to-left.
  const ops: { op: string; args: number[] }[] = []
  while ((match = regex.exec(str)) !== null) {
    ops.push({
      op: match[1],
      args: match[2].split(/[ ,]+/).map(Number),
    })
  }

  for (let i = ops.length - 1; i >= 0; i--) {
    const { op, args } = ops[i]
    let opMatrix = IDENTITY_MATRIX
    switch (op) {
      case 'matrix':
        opMatrix = args
        break
      case 'translate': {
        const [tx, ty = 0] = args
        opMatrix = [1, 0, 0, 1, tx, ty]
        break
      }
      case 'scale': {
        const [sx, sy = sx] = args
        opMatrix = [sx, 0, 0, sy, 0, 0]
        break
      }
      case 'rotate': {
        const [angle, cx = 0, cy = 0] = args
        const rad = (angle * Math.PI) / 180
        const cos = Math.cos(rad)
        const sin = Math.sin(rad)
        // Create rotation matrix around a center point
        const t1 = [1, 0, 0, 1, cx, cy]
        const rot = [cos, sin, -sin, cos, 0, 0]
        const t2 = [1, 0, 0, 1, -cx, -cy]
        opMatrix = multiplyMatrices(t1, multiplyMatrices(rot, t2))
        break
      }
    }
    currentMatrix = multiplyMatrices(opMatrix, currentMatrix)
  }

  return currentMatrix
}

function applyLinearTransform(x: number, y: number, m: number[]): Point {
  const [a, b, c, d, e, f] = m
  return {
    x: a * x + c * y + e,
    y: b * x + d * y + f,
  }
}

// Merge referenced gradient (href) into current. Current overrides referenced.
function resolveRef(defs: Defs, def: AnyDef, seen = new Set<string>()): AnyDef {
  if (!def.href) return def
  const id = def.href.replace('#', '')
  if (seen.has(id)) {
    // Circular reference detected, return def without href to stop recursion
    const newDef = { ...def }
    delete newDef.href
    return newDef
  }
  seen.add(id)
  const base = defs[id]
  if (!base) return def
  const resolvedBase = resolveRef(defs, base, seen)

  const commonResolved = {
    gradientUnits: def.gradientUnits ?? resolvedBase.gradientUnits,
    gradientTransform: def.gradientTransform ?? resolvedBase.gradientTransform,
    stops: def.stops.length ? def.stops : resolvedBase.stops,
    href: undefined, // Mark as resolved
  }

  if (def.kind === 'linear') {
    const resolvedLinear =
      resolvedBase.kind === 'linear' ? resolvedBase : ({} as Partial<LinearDef>)
    return {
      ...def,
      ...commonResolved,
      x1: def.x1 ?? resolvedLinear.x1,
      y1: def.y1 ?? resolvedLinear.y1,
      x2: def.x2 ?? resolvedLinear.x2,
      y2: def.y2 ?? resolvedLinear.y2,
    }
  }

  if (def.kind === 'radial') {
    const resolvedRadial =
      resolvedBase.kind === 'radial' ? resolvedBase : ({} as Partial<RadialDef>)
    return {
      ...def,
      ...commonResolved,
      cx: def.cx ?? resolvedRadial.cx,
      cy: def.cy ?? resolvedRadial.cy,
      r: def.r ?? resolvedRadial.r,
      fx: def.fx ?? resolvedRadial.fx,
      fy: def.fy ?? resolvedRadial.fy,
    }
  }

  // Fallback for unknown kinds, though should not be reached with current types
  return def
}

// Convert stops (apply opacity) and bake transform. Here we assume gradientUnits=userSpaceOnUse.
function toRuntimeGradient(def: AnyDef, boundingBox: BoundingBox): ShapeProps['fill'] | null {
  const resolved = resolveRef({}, def) // def already resolved in caller, keep fn pure if needed
  const stops = (resolved.stops || []).map((s) => ({
    offset: s.offset,
    color: [
      s.color[0],
      s.color[1],
      s.color[2],
      s.color[3] * (isFinite(s.opacity) ? s.opacity : 1),
    ] as [number, number, number, number],
  }))

  // gradient with matrix are treated as absolute in svg, position doesn't depend on shape(owner)
  if (resolved.gradientUnits != 'userSpaceOnUse' && !resolved.gradientTransform) {
    throw Error('gradient units is not userSpaceOnUse BUT there is no gradientTransform provided')
  }
  const tf = parseTransform(resolved.gradientTransform)

  if (resolved.kind === 'linear') {
    const x1_rel = resolved.x1 ?? 0
    const y1_rel = resolved.y1 ?? 0
    const x2_rel = resolved.x2 ?? 1
    const y2_rel = resolved.y2 ?? 0

    // if (resolved.gradientUnits === 'objectBoundingBox') {
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
  } else if (resolved.kind === 'radial') {
    const cx = resolved.cx ?? 0.5
    const cy = resolved.cy ?? 0.5
    const r = resolved.r ?? 0.5

    const center = applyLinearTransform(cx, cy, tf)
    console.log(cx, cy, tf, center)
    // To find the transformed radius, we transform a point on the original circle's
    // circumference and then find the vector from the new center.
    const pointOnCircle = applyLinearTransform(cx + r, cy, tf)
    const radiusX = { x: pointOnCircle.x, y: pointOnCircle.y }

    const pointOnCircleY = applyLinearTransform(cx, cy + r, tf)
    const radiusY = { x: pointOnCircleY.x, y: pointOnCircleY.y }

    radiusX.x -= boundingBox.min_x
    radiusX.y -= boundingBox.min_y
    radiusY.x -= boundingBox.min_x
    radiusY.y -= boundingBox.min_y
    // radiusX IS WROOOOONG

    const radiusRatio =
      Math.hypot(radiusY.x - center.x, radiusY.y - center.y) /
      Math.hypot(radiusX.x - center.x, radiusX.y - center.y)

    const bbWidth = boundingBox.max_x - boundingBox.min_x
    const bbHeight = boundingBox.max_y - boundingBox.min_y
    // center.x = center.x / bbWidth
    // center.y = 1 - center.y / bbHeight
    // radiusX.x = radiusX.x / bbWidth
    // radiusX.y = 1 - radiusX.y / bbHeight
    center.x = (center.x - boundingBox.min_x) / bbWidth
    center.y = 1 - (center.y - boundingBox.min_y) / bbHeight
    radiusX.x = radiusX.x / bbWidth
    radiusX.y = 1 - radiusX.y / bbHeight
    console.log('after norm radiusX', radiusX)

    // const r = resolved.r ?? 0.5
    // const c = applyLinearTransform(cx, svgHeight - cy, tf)
    // const fx = resolved.fx
    // const fy = resolved.fy
    // const focus =
    //   fx != null && fy != null ? applyLinearTransform(fx, svgHeight - fy, tf) : undefined
    // Approximate radius scale: take max scale component

    // const bbWidth = boundingBox.max_x - boundingBox.min_x
    // const bbHeight = boundingBox.max_y - boundingBox.min_y

    return {
      radial: {
        stops,
        center,
        destination: radiusX,
        radius_ratio: radiusRatio,
        // cx: c.x,
        // cy: c.y,
        // r: r * scaleMax,
        // fx: focus?.x ?? null,
        // fy: focus?.y ?? null,
      },
    }
  }
  return null
}

function getProps(node: ElementNode): Record<string, string | number> {
  if (typeof node.properties?.style === 'string') {
    const styleProps: Record<string, string | number> = {}
    node.properties.style.split(';').forEach((declaration) => {
      const [property, value] = declaration.split(':')
      if (property && value) {
        styleProps[property.trim()] = value.trim()
      }
    })
    // Direct properties override style properties
    return { ...styleProps, ...node.properties }
  }
  return node.properties || {}
}

function getGradientStops(nodes: ElementNode[]) {
  return nodes.map((stop) => {
    const stopProps = getProps(stop)
    return {
      offset: Number(stopProps.offset ?? 0),
      color: parseColor(String(stopProps['stop-color'] ?? '#000')),
      opacity: Number(stopProps['stop-opacity'] ?? 1),
    }
  })
}

export function collectDefs(node: Node, defs: Defs): void {
  if (!('children' in node)) return

  node.children.forEach((child) => {
    if (typeof child !== 'string') {
      if ('properties' in child && typeof child.properties === 'object') {
        const props = getProps(child)

        switch (child.tagName) {
          case 'linearGradient': {
            const id = String(props.id)

            const gradientUnits =
              props.gradientUnits === 'userSpaceOnUse'
                ? 'userSpaceOnUse'
                : props.gradientUnits === 'objectBoundingBox'
                ? 'objectBoundingBox'
                : undefined

            defs[id] = {
              kind: 'linear',
              id,
              x1: props.x1 != null ? Number(props.x1) : undefined,
              y1: props.y1 != null ? Number(props.y1) : undefined,
              x2: props.x2 != null ? Number(props.x2) : undefined,
              y2: props.y2 != null ? Number(props.y2) : undefined,
              gradientUnits,
              gradientTransform: (props.gradientTransform as string) ?? undefined,
              href: (props.href as string) || (props['xlink:href'] as string) || undefined,
              stops: getGradientStops(child.children as ElementNode[]),
            }
            return
          }
          case 'radialGradient': {
            const id = String(props.id)
            const gradientUnits =
              props.gradientUnits === 'userSpaceOnUse'
                ? 'userSpaceOnUse'
                : props.gradientUnits === 'objectBoundingBox'
                ? 'objectBoundingBox'
                : undefined

            defs[id] = {
              kind: 'radial',
              id,
              cx: props.cx != null ? Number(props.cx) : undefined,
              cy: props.cy != null ? Number(props.cy) : undefined,
              r: props.r != null ? Number(props.r) : undefined,
              fx: props.fx != null ? Number(props.fx) : undefined,
              fy: props.fy != null ? Number(props.fy) : undefined,
              gradientUnits,
              gradientTransform: (props.gradientTransform as string) ?? undefined,
              href: (props.href as string) || (props['xlink:href'] as string) || undefined,
              stops: getGradientStops(child.children as ElementNode[]),
            }
            return
          }
        }
      }
      collectDefs(child, defs)
    }
  })
}

export function createShapes(
  node: Node,
  defs: Defs,
  svgWidth: number,
  svgHeight: number,
  parentTransform: number[] = IDENTITY_MATRIX
): void {
  if (!('children' in node)) return

  let currTransform = parentTransform

  node.children.forEach((child) => {
    if (typeof child !== 'string') {
      if ('properties' in child && typeof child.properties === 'object') {
        const props = getProps(child)

        let paths: Point[][] | undefined = undefined

        switch (child.tagName) {
          case 'path':
            if (typeof props?.d !== 'string') {
              throw Error("Path without 'd' property")
            }
            paths = parsePathData(props.d as string).map((curve) => curve.points)
            break
          case 'rect':
            if (typeof props?.width !== 'number' || typeof props?.height !== 'number') {
              throw Error("Rect without 'width' or 'height' property")
            }
            paths = [parseRect(props.width, props.height)]
            break
          case 'ellipse':
            if (typeof props?.rx !== 'number' || typeof props?.ry !== 'number') {
              throw Error("Ellipse without 'rx' or 'ry' property")
            }
            if (typeof props?.cx !== 'number' || typeof props?.cy !== 'number') {
              throw Error("Ellipse without 'cx' or 'cy' property")
            }
            paths = [parseEllipse(props.cx, props.cy, props.rx, props.ry)]
            break
          case 'g':
            currTransform = parseTransform(props.transform as string | undefined, currTransform)
            break
        }

        if (paths) {
          //           if (props.id === 'eyelid_right') {
          //   console.log(paths)
          //   console.log(boundingBox)
          //   debugger
          // }
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
                const resolved = resolveRef(defs, def)

                /*
                  eyelid_right
                  shape width: 41.9, height: 29.8

                  start: x:29.5, y: 24.2
                  end: x: 10.8, y: 13.6
                */

                const grad = toRuntimeGradient(resolved, boundingBox)
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
                const resolved = resolveRef(defs, def)
                const grad = toRuntimeGradient(resolved, boundingBox)
                if (grad) serializedProps.stroke = grad
              }
            } else {
              const rgba = parseColor(stroke)
              serializedProps.stroke = { solid: rgba }
            }
          }

          const transform = props.transform as string | undefined
          if (transform) {
            currTransform = parseTransform(transform, currTransform)
          }
          const transformedPaths = paths.map((path) =>
            path.map((point) => applyLinearTransform(point.x, point.y, currTransform))
          )

          const correctedPaths = transformedPaths.map((path) =>
            path.map((p) => ({ x: p.x, y: svgHeight - p.y }))
          )
          console.log(child)
          console.log('defs', defs)
          console.log('correctedPaths', correctedPaths)
          console.log('serializedProps', serializedProps)
          Logic.addShape(0, correctedPaths, null, serializedProps, Textures.createSDF())
        }
      }
      createShapes(child, defs, svgWidth, svgHeight, currTransform)
    }
  })
}
