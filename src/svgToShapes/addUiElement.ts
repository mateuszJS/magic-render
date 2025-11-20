import * as Logic from 'logic/index.zig'
import * as Textures from 'textures'
import { BoundingBox } from './boundingBox'
import { ShapeData } from './collectShapesData'

export default function addUiElement(
  shapesData: ShapeData[],
  uiElementType: UiElementType,
  maxY?: number
): void {
  if (!maxY) {
    const totalBB = new BoundingBox()
    shapesData.forEach((shape) => {
      totalBB.addBox(shape.boundingBox)
    })

    maxY = totalBB.max_y
  }

  shapesData.forEach(({ paths }) => {
    const correctedPaths = paths.map((path) => path.map((p) => ({ x: p.x, y: maxY - p.y })))
    Logic.importUiElement(uiElementType, correctedPaths, Textures.createSDF())
  })
}
