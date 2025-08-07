interface Point {
  x: number
  y: number
}

interface PointUV {
  x: number
  y: number
  u: number
  v: number
}

interface BoundingBox {
  min_x: number
  min_y: number
  max_x: number
  max_y: number
}

type ShapeProps = Partial<{
  fill_color: [number, number, number, number]
  stroke_color: [number, number, number, number]
  stroke_width: number
}>

type ZigF32Array = { typedArray: Float32Array }
type ZigAssetInput = {
  id: number
  points: PointUV[]
  texture_id: number
}
type ImageAssetOutput = {
  id: number
  points: PointUV[]
  texture_id: number
}
type ShapeAssetOutput = {
  id: number
  points: PointUV[]
  paths: Point[][]
  texture_id: number
}
type ZigAssetOutput =
  | { img: ImageAssetOutput; shape: null }
  | { img: null; shape: ShapeAssetOutput }
type ArrayPointerDataView = {
  '*': PointerDataView
}
type PointerDataView = {
  dataView: DataView
}

declare module '*.zig' {
  export const initState: (width: number, height: number, max_texture_size: number) => void
  export const addAsset: (maybe_asset_id: number, points: PointUV[], texture_id: number) => void
  export const removeAsset: () => void
  export const resetAssets: (assets: ZigAssetInput[], with_snapshot: boolean) => void

  export const onUpdatePick: (id: number) => void
  export const onPointerDown: (x: number, y: number) => void
  export const onPointerUp: () => void
  export const onPointerMove: (x: number, y: number) => void
  export const onPointerLeave: VoidFunction
  export const commitChanges: VoidFunction
  export const updateRenderScale: (render_scale: number) => void

  export const connectWebGpuPrograms: (programs: {
    draw_texture: (vertex_data: PointerDataView, texture_id: number) => void
    draw_triangle: (vertex_data: ArrayPointerDataView) => void
    draw_msdf: (vertex_data: ArrayPointerDataView, texture_id: number) => void
    pick_texture: (vertex_data: ArrayPointerDataView, texture_id: number) => void
    pick_triangle: (vertex_data: ArrayPointerDataView) => void
    draw_shape: (
      curves_data: ArrayPointerDataView,
      bound_box_data: ArrayPointerDataView,
      uniformData: PointerDataView
    ) => void
  }) => void
  export const connectOnAssetUpdateCallback: (cb: (data: ZigAssetOutput[]) => void) => void
  export const connectOnAssetSelectionCallback: (cb: (data: number) => void) => void
  export const connectCacheCallbacks: (
    start_cache: (
      texture_id: number | null,
      box: BoundingBox,
      width: number,
      height: number
    ) => number,
    end_cache: VoidFunction
  ) => void

  export const renderDraw: VoidFunction
  export const renderPick: VoidFunction
  export const destroyState: VoidFunction
  export const setTool: (tool: number) => void

  export const importIcons: (data: number[]) => void

  export const addShape: (
    paths: Array<Array<[Point, Point, Point, Point]>>,
    props: ShapeProps
  ) => void
}
