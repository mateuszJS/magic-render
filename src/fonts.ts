import opentype from 'opentype.js'
import paper from 'paper'
import parsePathData from 'svgToShapes/parsePathData'
import * as Textures from 'textures'
import * as Logic from 'logic/index.zig'
import { Point } from 'types'
import decompressWoff2 from 'utils/decompressWoff2.mjs'
import { isStraightHandle } from 'svgToShapes/utils'
import { STRAIGHT_LINE_HANDLE } from 'svgToShapes/const'
import * as PreviewTrigger from './previewTrigger'

const DEFAULT_SPACE = 250 // expressed in font units
const ENTER = 10

let fonts: Map<number, opentype.Font | null>
let getFontUrl: (fontId: number) => string

export function init(getFontUrlFn: (fontId: number) => string) {
  fonts = new Map<number, opentype.Font | null>()
  getFontUrl = getFontUrlFn
  paper.setup(new paper.Size(1, 1))
}

export async function loadFont(fontId: number) {
  if (fonts.has(fontId)) {
    return
  }

  fonts.set(fontId, null)
  let fontBuffer: ArrayBuffer | null = null
  try {
    PreviewTrigger.updateResourcesFlag('font-load-start')
    const url = getFontUrl(fontId)
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
      try {
        const decompressed = decompressWoff2.decompress(fontBuffer)
        // Create a copy of the buffer because decompressed is a view into WASM memory
        // and .buffer would return the whole WASM heap
        fontBuffer = decompressed.slice(0).buffer
        fonts.set(fontId, opentype.parse(fontBuffer))
        Logic.addFont(fontId)
      } catch (woff2Err) {
        console.error('Failed to decompress/parse WOFF2 font', woff2Err)
      }
    } else {
      console.error('Failed to load font', err)
    }
  } finally {
    PreviewTrigger.updateResourcesFlag('font-load-end')
  }
}

export function getKerning(fontId: number, charA: number, charB: number): number {
  const font = fonts.get(fontId)

  if (!font) {
    throw Error('getKerning, font not loaded yet, font id: ' + fontId)
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

  // in case a character is created out of multiple overlapping paths,
  // we have to intersect and unite them;
  // otherwise SDF paths will become incorrect because of the within-shape path.
  // By intersection & union we ensure it's only the outline,
  // not paths inside shapes.
  paper.project.activeLayer.removeChildren()
  const item = new paper.CompoundPath(d)
  const unitedItem = item.unite(item)
  const unitedPathData = unitedItem.pathData
  // Clean up Paper.js items to prevent memory leaks
  item.remove()
  unitedItem.remove()

  const paths = parsePathData(unitedPathData)
  const correctedPaths: Point[] = []

  const { x1, x2, y1, y2 } = path.getBoundingBox()

  paths.forEach((path) => {
    for (let i = 0; i < path.length; i += 3) {
      const reflected = path
        .slice(i, i + 4)
        .map((p) => (isStraightHandle(p) ? STRAIGHT_LINE_HANDLE : { x: p.x - x1, y: -(p.y - y2) }))
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

  const noVisual = width <= Number.EPSILON || correctedPaths.length === 0

  const result = new Logic.SerializedCharDetails({
    x: x1,
    y: -y2,
    width,
    height: -y1 - -y2,
    sdf_texture_id: noVisual ? null : Textures.createSDF(),
  })

  result.setPaths(correctedPaths)

  return result
}
