import fontFile from '../icons/GoogleSans-Regular.ttf'
import opentype from 'opentype.js'
import type { Font } from 'opentype.js'
// import createShapes from 'svgToShapes/createShapes'
// import { ElementNode } from 'svg-parser'
// import collectShapesData from 'svgToShapes/collectShapesData'
import parsePathData from 'svgToShapes/parsePathData'
import * as Textures from 'textures'
import * as Logic from 'logic/index.zig'

let font: Font

export async function loadFont() {
  const buffer = fetch(fontFile).then((res) => res.arrayBuffer())
  font = opentype.parse(await buffer)
}

export function getCharData(font_id: number, char_code: number): Logic.SerializedCharDetails {
  const char = String.fromCharCode(char_code)
  const d = font.getPath(char, 0, 0, 1).toPathData(5)
  const paths = parsePathData(d)
  const correctedPaths: Point[] = []

  paths.forEach((path) => {
    for (let i = 0; i < path.length; i += 3) {
      const reflected = path.slice(i, i + 4).map((p) => ({ x: p.x, y: -p.y }))
      correctedPaths.push(...reflected)
    }
    correctedPaths.splice(-1)
  })

  const result = new Logic.SerializedCharDetails({
    width: 1,
    height: 1,
    sdf_texture_id: Textures.createSDF(),
  })
  result.setPaths(correctedPaths)

  return result
}
// const svgNode: ElementNode = {
//   type: 'element', // pretend it's svg-parser created object
//   children: [],
//   tagName: 'path',
//   properties: {
//     d,
//     fill: '#fff',
//   },
// }
// const shapesData = collectShapesData(svgNode, {})
// createShapes(shapesData)

// console.log(font.stringToGlyphs('Hello world'))
// console.log(font.getKerningValue(font.charToGlyph('w'), font.charToGlyph('o')))
