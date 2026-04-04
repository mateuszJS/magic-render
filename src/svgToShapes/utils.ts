import { ElementNode, Node } from 'svg-parser'
import { AttrValue } from './definitions'
import { Color, Point } from 'types'

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

export function getNum(x: AttrValue, fallback: number = 0): number {
  if (typeof x === 'number') return x
  const n = Number(x)
  if (isNaN(n)) return fallback
  return n
}

export function isElementNode(node: string | Node): node is ElementNode {
  return typeof node !== 'string' && node.type === 'element'
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
