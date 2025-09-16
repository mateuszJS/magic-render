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

type Color = [number, number, number, number]

type UiElementType = 0

type GradientStop = {
  color: Color
  offset: number // 0..1
}

type LinearGradient = {
  start: Point
  end: Point
  stops: GradientStop[]
}

type RadialGradient = {
  radius_ratio: number
  stops: GradientStop[]
  center: Point
  destination: Point
}

type SdfEffect = {
  dist_start: number
  dist_end: number
  fill: { linear: LinearGradient } | { radial: RadialGradient } | { solid: Color }
}

type ShapeProps = {
  sdf_effects: SdfEffect[]
  filter: { gaussianBlur: Point } | null
  opacity: number
}

type ImageAssetOutput = {
  id: number
  points: PointUV[]
  texture_id: number
}

type ShapeAssetOutput = {
  id: number
  paths: Point[][]
  props: ShapeProps
  bounds: PointUV[]
  sdf_texture_id: number
  cache_texture_id: number | null
}

type TextAssetOutput = {
  id: number
  content: string
  bounds: PointUV[]
  max_width: number
  font_size: number
}

type ImageAssetInput = {
  id: number
  points: PointUV[]
  texture_id: number
}

type ShapeAssetInput = {
  id: number
  paths: Point[][]
  props: ShapeProps
  bounds: PointUV[] | null
  sdf_texture_id: number
  cache_texture_id: number | null
}

type TextAssetInput = {
  id: number
  content: string
  bounds: PointUV[] | null
  max_width: number
  font_size: number
}

type ZigAssetOutput =
  | { img: ImageAssetOutput }
  | { shape: ShapeAssetOutput }
  | { text: TextAssetOutput }
type ZigAssetInput =
  | { img: ImageAssetInput }
  | { shape: ShapeAssetInput }
  | { text: TextAssetInput }

type ArrayPointerDataView = {
  '*': PointerDataView
}
type PointerDataView = {
  dataView: DataView
}

type ShapeDrawUniform =
  | { solid: PointerDataView }
  | { linear: PointerDataView }
  | { radial: PointerDataView }

declare module '*.zig' {
  export const initState: (
    width: number,
    height: number,
    max_texture_size: number,
    max_buffer_size: number
  ) => void
  export const addImage: (maybe_asset_id: number, points: PointUV[], texture_id: number) => void
  export const updateCache: VoidFunction
  export const addShape: (
    maybe_asset_id: number,
    paths: Point[][],
    bounds: PointUV[] | null,
    props: Partial<ShapeProps>,
    sdf_texture_id: number,
    cache_texture_id: null | number
  ) => number /* id */
  export const addShapeBegin: VoidFunction
  export const addShapeFinish: VoidFunction
  export const removeAsset: () => void
  export const resetAssets: (assets: ZigAssetInput[], with_snapshot: boolean) => void

  export const onUpdatePick: (id: number) => void
  export const onPointerDown: (x: number, y: number) => void
  export const onPointerUp: () => void
  export const onPointerMove: (x: number, y: number) => void
  export const onPointerLeave: VoidFunction
  export const commitChanges: VoidFunction
  export const updateRenderScale: (render_scale: number) => void
  export const updateTextContent: (text: string) => void

  // Type definition for SerializedCharDetails as a constructible class
  export interface SerializedCharDetails {
    x: number
    y: number
    width: number
    height: number
    sdf_texture_id: number | null
    setPaths(paths: Point[]): void // we have to call std.mem.Allocator.dupe() to allocate permament memory in zig
  }

  export const SerializedCharDetails: new ({
    x,
    y,
    width,
    height,
    sdf_texture_id,
  }: {
    x: number
    y: number
    width: number
    height: number
    sdf_texture_id: number | null
  }) => SerializedCharDetails

  export const Point: new ({ x, y }: { x: number; y: number }) => Point

  export const PtrI32: new (p: Point[][]) => Point[][]

  export const connectWebGpuPrograms: (programs: {
    draw_texture: (vertex_data: PointerDataView, texture_id: number) => void
    draw_triangle: (vertex_data: ArrayPointerDataView) => void
    pick_texture: (vertex_data: ArrayPointerDataView, texture_id: number) => void
    pick_triangle: (vertex_data: ArrayPointerDataView) => void
    draw_blur: (
      texture_id: number,
      iterations: number,
      filterSizePerPassX: number,
      filterSizePerPassY: number,
      sigmaPerPassX: number,
      sigmaPerPassY: number
    ) => void
    compute_shape: (
      curves_data: ArrayPointerDataView,
      width: number,
      height: number,
      sdf_texture_id: number
    ) => void
    draw_shape: (
      bound_box_data: ArrayPointerDataView,
      uniformData: ShapeDrawUniform,
      sdf_texture_id: number
    ) => void
    pick_shape: (
      bound_box_data: ArrayPointerDataView,
      uniformData: PointerDataView,
      sdf_texture_id: number
    ) => void
  }) => void
  export const connectOnAssetUpdateCallback: (cb: (data: ZigAssetOutput[]) => void) => void
  export const connectOnAssetSelectionCallback: (cb: (data: number) => void) => void
  export const connectCreateSdfTexture: (cb: () => number) => void
  export const connectCacheCallbacks: (
    create_cache_texture: () => number,
    start_cache: (texture_id: number, box: BoundingBox, width: number, height: number) => void,
    end_cache: VoidFunction
  ) => void
  export const connectTyping: (
    enable: (text: string) => void,
    disable: VoidFunction,
    update: (text: string) => void,
    getCharData: (font_id: number, char_code: number) => CharDetails,
    getKerning: (font_id: number, char_code: number) => number
  ) => void
  export const setCaretPosition: (selection_start: number, selection_end: number) => void

  export const tick: (time: DOMHighResTimeStamp) => void
  export const calculateShapesSDF: VoidFunction
  export const renderDraw: VoidFunction
  export const renderPick: VoidFunction
  export const deinitState: VoidFunction
  export const setTool: (tool: number) => void

  export const importUiElement: (
    id: UiElementType,
    paths: Point[][],
    sdf_texture_id: number
  ) => void
  export const generateUiElementsSdf: VoidFunction

  // export const page_allocator:
}
