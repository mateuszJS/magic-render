import fontFile from '../icons/GoogleSans-Regular.ttf'
import opentype from 'opentype.js'
import type { Font } from 'opentype.js'
import parsePathData from 'svgToShapes/parsePathData'
import * as Textures from 'textures'
import * as Logic from 'logic/index.zig'

const DEFAULT_SPACE = 250 // expressed in font units
const ENTER = 10

let font: Font

export async function loadFont() {
  const buffer = fetch(fontFile).then((res) => res.arrayBuffer())
  font = opentype.parse(await buffer)
}

export function getKerning(charA: number, charB: number): number {
  const ca = String.fromCharCode(charA)
  const cb = String.fromCharCode(charB)
  const leftGlyph = font.charToGlyph(ca)
  const rightGlyph = font.charToGlyph(cb)
  const font_units = font.getKerningValue(leftGlyph, rightGlyph)
  return font_units / font.unitsPerEm
}

export function getCharData(font_id: number, char_code: number): Logic.SerializedCharDetails {
  const char = String.fromCharCode(char_code)
  const path = font.getPath(char, 0, 0, 1)
  const d = path.toPathData(5)
  const paths = parsePathData(d)
  const correctedPaths: Point[] = []

  const { x1, x2, y1, y2 } = path.getBoundingBox()

  paths.forEach((path) => {
    for (let i = 0; i < path.length; i += 3) {
      const reflected = path.slice(i, i + 4).map((p) => ({ x: p.x - x1, y: -(p.y - y2) }))
      correctedPaths.push(...reflected)
    }
    correctedPaths.splice(-1)
  })

  let width = x2 - x1
  if (width === 0) {
    const glyph = font.charToGlyph(' ')
    width = (glyph.advanceWidth ?? DEFAULT_SPACE) / font.unitsPerEm
  }

  if (char_code == ENTER) {
    width = 0
  }

  const result = new Logic.SerializedCharDetails({
    x: x1,
    y: -y2,
    width,
    height: -y1 - -y2,
    sdf_texture_id: correctedPaths.length > 0 ? Textures.createSDF() : null,
  })

  result.setPaths(correctedPaths)

  return result
}
