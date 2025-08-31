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
type Def = Record<string, AnyDef>

// Parse a gradientTransform into separate operations
function parseTransform(str: string | undefined): {
  translate: { x: number; y: number }
  scale: { x: number; y: number }
  rotate: number
  matrix?: number[]
} {
  const res = { translate: { x: 0, y: 0 }, scale: { x: 1, y: 1 }, rotate: 0 }
  if (!str) return res

  const matrixMatch = str.match(/matrix\(([^)]+)\)/)
  if (matrixMatch) {
    const [a, b, c, d, e, f] = matrixMatch[1].split(/[ ,]+/).map(Number)
    return { ...res, matrix: [a, b, c, d, e, f] }
  }

  const t = str.match(/translate\(([^)]+)\)/)
  if (t) {
    const [x, y] = t[1].split(/[ ,]+/).map(Number)
    res.translate.x = x || 0
    res.translate.y = y || 0
  }
  const s = str.match(/scale\(([^)]+)\)/)
  if (s) {
    const parts = s[1].split(/[ ,]+/).map(Number)
    res.scale.x = parts[0] ?? 1
    res.scale.y = parts[1] ?? parts[0] ?? 1
  }
  const r = str.match(/rotate\(([^)]+)\)/)
  if (r) res.rotate = Number(r[1]) || 0
  return res
}

function applyLinearTransform(x: number, y: number, tf: ReturnType<typeof parseTransform>) {
  if (tf.matrix) {
    const [a, b, c, d, e, f] = tf.matrix
    return {
      x: a * x + c * y + e,
      y: b * x + d * y + f,
    }
  }
  // scale -> rotate -> translate
  const sx = x * tf.scale.x
  const sy = y * tf.scale.y
  const rad = (tf.rotate * Math.PI) / 180
  const rx = sx * Math.cos(rad) - sy * Math.sin(rad)
  const ry = sx * Math.sin(rad) + sy * Math.cos(rad)
  return { x: rx + tf.translate.x, y: ry + tf.translate.y }
}

// Merge referenced gradient (href) into current. Current overrides referenced.
function resolveRef(defs: Def, def: AnyDef, seen = new Set<string>()): AnyDef {
  if (!def.href) return def
  const id = def.href.replace('#', '')
  if (seen.has(id)) return def
  seen.add(id)
  const base = defs[id]
  if (!base) return def
  const resolvedBase = resolveRef(defs, base, seen)
  if (def.kind === 'linear' && resolvedBase.kind === 'linear') {
    return {
      kind: 'linear',
      id: def.id,
      x1: def.x1 ?? resolvedBase.x1,
      y1: def.y1 ?? resolvedBase.y1,
      x2: def.x2 ?? resolvedBase.x2,
      y2: def.y2 ?? resolvedBase.y2,
      gradientUnits: def.gradientUnits ?? resolvedBase.gradientUnits,
      gradientTransform: def.gradientTransform ?? resolvedBase.gradientTransform,
      href: undefined,
      stops: def.stops.length ? def.stops : resolvedBase.stops,
    }
  } else if (def.kind === 'radial' && resolvedBase.kind === 'radial') {
    return {
      kind: 'radial',
      id: def.id,
      cx: def.cx ?? resolvedBase.cx,
      cy: def.cy ?? resolvedBase.cy,
      r: def.r ?? resolvedBase.r,
      fx: def.fx ?? resolvedBase.fx,
      fy: def.fy ?? resolvedBase.fy,
      gradientUnits: def.gradientUnits ?? resolvedBase.gradientUnits,
      gradientTransform: def.gradientTransform ?? resolvedBase.gradientTransform,
      href: undefined,
      stops: def.stops.length ? def.stops : resolvedBase.stops,
    }
  }
  return def
}

// Convert stops (apply opacity) and bake transform. Here we assume gradientUnits=userSpaceOnUse.
function toRuntimeGradient(
  def: AnyDef,
  svgHeight: number,
  boundingBox: BoundingBox
): ShapeProps['fill'] | null {
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
  const tf = parseTransform(resolved.gradientTransform)
  console.log('----------', resolved.kind)
  if (resolved.kind === 'linear') {
    const x1_rel = resolved.x1 ?? 0
    const y1_rel = resolved.y1 ?? 0
    const x2_rel = resolved.x2 ?? 1
    const y2_rel = resolved.y2 ?? 0

    // let p1: { x: number; y: number }
    // let p2: { x: number; y: number }

    const bbWidth = boundingBox.max_x - boundingBox.min_x
    const bbHeight = boundingBox.max_y - boundingBox.min_y

    // if (resolved.gradientUnits === 'objectBoundingBox') {
    const x1 = boundingBox.min_x + x1_rel * bbWidth
    const y1 = boundingBox.min_y + y1_rel * bbHeight
    const x2 = boundingBox.min_x + x2_rel * bbWidth
    const y2 = boundingBox.min_y + y2_rel * bbHeight
    const p1 = applyLinearTransform(x1, y1, tf)
    const p2 = applyLinearTransform(x2, y2, tf)
    // } else {
    //   p1 = applyLinearTransform(x1_rel, svgHeight - y1_rel, tf)
    //   p2 = applyLinearTransform(x2_rel, svgHeight - y2_rel, tf)
    // }

    p1.x = p1.x / bbWidth
    p1.y = p1.y / bbHeight
    p2.x = p2.x / bbWidth
    p2.y = p2.y / bbHeight
    console.log({ linear: { stops, start: p1, end: p2 } })
    return { linear: { stops, start: p1, end: p2 } }
  } else if (resolved.kind === 'radial') {
    const cx = resolved.cx ?? 0.5
    const cy = resolved.cy ?? 0.5
    const r = resolved.r ?? 0.5
    const c = applyLinearTransform(cx, svgHeight - cy, tf)
    const fx = resolved.fx
    const fy = resolved.fy
    const focus =
      fx != null && fy != null ? applyLinearTransform(fx, svgHeight - fy, tf) : undefined
    // Approximate radius scale: take max scale component
    const scaleMax = Math.max(
      parseTransform(resolved.gradientTransform).scale.x,
      parseTransform(resolved.gradientTransform).scale.y
    )
    return {
      radial: {
        stops,
        center: c,
        radius: { x: 100, y: 100 },
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

export default function createShapes(
  node: Node,
  defs: Def,
  svgWidth: number,
  svgHeight: number
): void {
  if (!('children' in node)) return

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

        if (paths) {
          const boundingBox = getBoundingBox(paths)
          const bbHeight = boundingBox.max_y - boundingBox.min_y

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
                const grad = toRuntimeGradient(resolved, bbHeight, boundingBox)
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
                const grad = toRuntimeGradient(resolved, bbHeight, boundingBox)
                if (grad) serializedProps.stroke = grad
              }
            } else {
              const rgba = parseColor(stroke)
              serializedProps.stroke = { solid: rgba }
            }
          }
          const correctedPaths = paths.map((path) =>
            path.map((p) => ({ x: p.x, y: svgHeight - p.y }))
          )
          console.log('serializedProps', serializedProps)
          Logic.addShape(0, correctedPaths, null, serializedProps, Textures.createSDF())
        }
      }
      createShapes(child, defs, svgWidth, svgHeight)
    }
  })
}
