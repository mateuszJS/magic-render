import opentype from 'opentype.js'
import parsePathData from 'svgToShapes/parsePathData'
import * as Textures from 'textures'
import * as Logic from 'logic/index.zig'
import { Point } from 'types'
import decompressWoff2 from 'utils/decompressWoff2.mjs'

const DEFAULT_SPACE = 250 // expressed in font units
const ENTER = 10

const fonts = new Map<number, opentype.Font | null>()

export async function loadFont(url: string, fontId: number) {
  if (fonts.has(fontId)) {
    return
  }

  fonts.set(fontId, null)
  let fontBuffer: ArrayBuffer | null = null
  try {
    const res = await fetch(url)
    fontBuffer = await res.arrayBuffer()
    fonts.set(fontId, opentype.parse(fontBuffer))
    Logic.addFont(fontId)
  } catch (err) {
    if (
      err instanceof Error &&
      err.message.includes('Unsupported OpenType signature wOF2') &&
      fontBuffer
    ) {
      const deocmpreassed = decompressWoff2.decompress(fontBuffer)
      // Create a copy of the buffer because deocmpreassed is a view into WASM memory
      // and .buffer would return the whole WASM heap
      fontBuffer = deocmpreassed.slice(0).buffer
      fonts.set(fontId, opentype.parse(fontBuffer))
      Logic.addFont(fontId)
    } else {
      console.error('Failed to load font', err)
    }
  }
}

export function getKerning(fontId: number, charA: number, charB: number): number {
  const font = fonts.get(fontId)

  if (!font) {
    return 0
  }

  const ca = String.fromCharCode(charA)
  const cb = String.fromCharCode(charB)
  const leftGlyph = font.charToGlyph(ca)
  const rightGlyph = font.charToGlyph(cb)
  const font_units = font.getKerningValue(leftGlyph, rightGlyph)
  return font_units / font.unitsPerEm
}

export function getCharData(fontId: number, char_code: number): Logic.SerializedCharDetails {
  const font = fonts.get(fontId)

  if (!font) {
    throw Error('getCharData, font not loaded yet, font id: ' + fontId)
  }

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
