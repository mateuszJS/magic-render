import { ZigAsset } from 'types'
import { ShapeData } from './collectShapesData'
import { BoundingBox } from './boundingBox'
import { DEFAULT_BOUNDS } from 'consts'
import * as Textures from 'textures'

export default function getShapesZigAssets(shapesData: ShapeData[], maxY?: number): ZigAsset[] {
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
      shape: {
        id: 0,
        paths: correctedPaths,
        bounds: DEFAULT_BOUNDS,
        props,
        sdf_texture_id: Textures.createSDF(),
        cache_texture_id: null,
      },
    }
  })
}
