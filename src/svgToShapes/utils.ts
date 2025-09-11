import { ElementNode, Node } from 'svg-parser'
import { AttrValue, Def } from './definitions'
import parsePathData from './parsePathData'

const STRAIGHT_LINE_THRESHOLD = 1e10

export function isStraightHandle(p: Point) {
  return p.x > STRAIGHT_LINE_THRESHOLD
}

// we use canvas to support ALL possible way of describing color in CSS
export function parseColor(cssColor: string, overrideAlpha = 1): Color {
  // Create a temporary canvas element
  const canvas = new OffscreenCanvas(1, 1)
  const ctx = canvas.getContext('2d')!

  // Set the fillStyle to the CSS color and draw a 1x1 rectangle
  ctx.fillStyle = cssColor
  ctx.fillRect(0, 0, 1, 1)

  // Read the pixel data from the canvas
  const imageData = ctx.getImageData(0, 0, 1, 1)
  const [r, g, b, a] = imageData.data

  // Return normalized RGBA values (0-1 range)
  return [
    (r / 255) * overrideAlpha, // red
    (g / 255) * overrideAlpha, // green
    (b / 255) * overrideAlpha, // blue
    (a / 255) * overrideAlpha, // alpha
  ]
}

export function getProps(node: ElementNode): Def {
  let rawProps = node.properties
  if (typeof node.properties?.style === 'string') {
    const styleProps = {} as Record<string, string | number>
    node.properties.style.split(';').forEach((declaration) => {
      const [property, value] = declaration.split(':')
      if (property && value) {
        styleProps[property.trim()] = value.trim()
      }
    })
    // Direct properties override style properties
    rawProps = { ...styleProps, ...node.properties }
  }

  if (!rawProps) return {}

  const def: Def = { ...rawProps }

  if ('d' in def) {
    def.paths = parsePathData(def.d as string)
    delete def.d
  }

  if ('gradientTransform' in rawProps) {
    def.gradientTransform = parseTransform(String(rawProps.gradientTransform))
  }

  if (
    (node.tagName === 'linearGradient' || node.tagName === 'radialGradient') &&
    node.children.length > 0
  ) {
    def.stops = getGradientStops(node.children)
  }

  if (node.tagName === 'filter' && node.children.length == 1 && isElementNode(node.children[0])) {
    addFilterProps(def, node.children[0])
  }

  return def
}

export function ensureNumber(x: AttrValue, fallback: number = 0): number {
  if (typeof x === 'number') return x
  const n = Number(x)
  if (isNaN(n)) return fallback
  return n
}

export function isElementNode(node: string | Node): node is ElementNode {
  return typeof node !== 'string' && node.type === 'element'
}

function getGradientStops(nodes: Array<string | Node>) {
  return nodes.map((stop) => {
    if (!isElementNode(stop)) {
      return { offset: 0, color: [0, 0, 0, 0] as Color }
    }
    const stopProps = getProps(stop)
    const color = parseColor(String(stopProps['stop-color'] ?? '#000'))
    color[3] = ensureNumber(stopProps['stop-opacity'], 1)

    return {
      offset: Number(stopProps.offset ?? 0),
      color,
    }
  })
}

export const IDENTITY_MATRIX = [1, 0, 0, 1, 0, 0]

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
export function parseTransform(
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

function addFilterProps(def: Def, child: ElementNode) {
  if (child.tagName === 'feGaussianBlur') {
    def.type = 'gaussian-blur'

    const v = child.properties?.stdDeviation
    let sx = 0
    let sy = 0
    if (typeof v === 'number') {
      sx = v
      sy = v
    } else if (typeof v === 'string') {
      const parts = v.trim().split(/[ ,]+/).filter(Boolean)
      if (parts.length >= 2) {
        sx = ensureNumber(parts[0], 0)
        sy = ensureNumber(parts[1], 0)
      } else if (parts.length === 1) {
        sx = ensureNumber(parts[0], 0)
        sy = sx
      }
    }
    def.stdDeviation = [sx, sy]
  }
}
