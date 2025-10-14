import type * as types from './src/types'

declare global {
  /* expose types globally to make the available in *.zig ambient declaration.
  Import & exports in ambient declaration are forbidden.
  Also these types are needed to be exported from the package.
  Otherwise if those are needed only internally, we could move them to ./src/logic/index.d.ts */
  namespace zig {
    type Point = types.Point
    type PointUV = types.PointUV
    type BoundingBox = types.BoundingBox
    type Id = types.Id
    type ShapeProps = types.ShapeProps
    type ZigAsset = types.ZigAsset
  }
}
