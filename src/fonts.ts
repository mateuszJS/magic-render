import fontFile from '../icons/GoogleSans-Regular.ttf'
import opentype from 'opentype.js'
import type { Font } from 'opentype.js'
import parsePathData from 'svgToShapes/parsePathData'
import * as Textures from 'textures'
import * as Logic from 'logic/index.zig'

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
  return font.getKerningValue(leftGlyph, rightGlyph)
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

  const result = new Logic.SerializedCharDetails({
    x: x1,
    y: -y2,
    width: x2 - x1,
    height: -y1 - -y2,
    sdf_texture_id: Textures.createSDF(),
  })
  result.setPaths(correctedPaths)

  return result
}
