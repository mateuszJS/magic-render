import * as Logic from 'logic/index.zig'
import * as Textures from 'textures'
import { BoundingBox } from './boundingBox'
import { ShapeData } from './collectShapesData'

export default function createShapes(
  shapesData: ShapeData[],
  maxY?: number,
  uiElementType?: UiElementType
): void {
  if (!maxY) {
    const totalBB = new BoundingBox()
    shapesData.forEach((shape) => {
      totalBB.addBox(shape.boundingBox)
    })

    maxY = totalBB.max_y
  }

  shapesData.forEach(({ paths, props }) => {
    const correctedPaths = paths.map((path) => path.map((p) => ({ x: p.x, y: maxY - p.y })))

    if (uiElementType !== undefined) {
      Logic.importUiElement(uiElementType, correctedPaths, Textures.createSDF())
      return // We expect all ui elements to have just one path
    } else {
      Logic.addShape(0, correctedPaths, null, props, Textures.createSDF(), null)
    }
  })
}
