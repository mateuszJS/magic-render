import { PointUV, Asset } from 'types'
import { ShapeData } from './collectShapesData'
import { BoundingBox } from './boundingBox'
import * as Textures from 'textures'

export const DEFAULT_BOUNDS: PointUV[] = [
  { x: 0, y: 1, u: 0, v: 1 },
  { x: 1, y: 1, u: 1, v: 1 },
  { x: 1, y: 0, u: 1, v: 0 },
  { x: 0, y: 0, u: 0, v: 0 },
]

export default function getShapesZigAssets(shapesData: ShapeData[], maxY?: number): Asset[] {
  if (!maxY) {
    const totalBB = new BoundingBox()
    shapesData.forEach((shape) => {
      totalBB.addBox(shape.boundingBox)
    })

    maxY = totalBB.max_y
  }

  return shapesData.map(({ paths, props }) => {
    const correctedPaths = paths.map((path) => path.map((p) => ({ x: p.x, y: maxY - p.y })))

    return {
      id: 0,
      paths: correctedPaths,
      bounds: DEFAULT_BOUNDS,
      props,
      sdf_texture_id: Textures.createSDF(),
      cache_texture_id: null,
    }
  })
}
