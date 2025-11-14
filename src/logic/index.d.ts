// types below does not need to be exported from this package
type UiElementType = 0

type ArrayPointerDataView = {
  '*': PointerDataView
}
type PointerDataView = {
  dataView: DataView<ArrayBuffer>
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
  export const addImage: (maybe_asset_id: number, bounds: zig.PointUV[], texture_id: number) => void
  export const updateCache: VoidFunction
  export const addShape: (
    maybe_asset_id: number,
    paths: zig.Point[][],
    bounds: zig.PointUV[] | null,
    props: Partial<zig.ShapeProps>,
    sdf_texture_id: number,
    cache_texture_id: null | number
  ) => number /* id */
  export const addShapeBegin: VoidFunction
  export const addShapeFinish: VoidFunction
  export const removeAsset: () => void
  export const resetAssets: (assets: zig.ZigAsset[], with_snapshot: boolean) => void

  export const onUpdatePick: (id: zig.Id) => void
  export const onPointerDown: (x: number, y: number) => void
  export const onPointerUp: () => void
  export const onPointerMove: (x: number, y: number) => void
  export const onPointerDoubleClick: VoidFunction
  export const onUpdateToolCallback: (cb: (new_tool: number) => void) => void
  export const onPointerLeave: VoidFunction
  export const commitChanges: VoidFunction
  export const updateRenderScale: (render_scale: number) => void
  export const updateTextContent: (
    text: string,
    selection_start: number,
    selection_end: number
  ) => {
    content: string
    selection_start: number
    selection_end: number
  }

  // Type definition for SerializedCharDetails as a constructible class
  export interface SerializedCharDetails {
    x: number
    y: number
    width: number
    height: number
    sdf_texture_id: number | null
    setPaths(paths: zig.Point[]): void // we have to call std.mem.Allocator.dupe() to allocate permament memory in zig
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

  export const Point: new ({ x, y }: { x: number; y: number }) => zig.Point

  export const PtrI32: new (p: zig.Point[][]) => zig.Point[][]

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
    clear_sdf: (
      sdfTextureId: number,
      computeDepthTextureId: number,
      width: number,
      height: number
    ) => void
    combine_sdf: (
      destinationTexId: number,
      sourceTexId: number,
      computeDepthTextureId: number,
      uniformData: PointerDataView
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
  export const connectOnAssetUpdateCallback: (cb: (data: zig.ZigAsset[]) => void) => void
  export const connectOnAssetSelectionCallback: (cb: (data: zig.Id) => void) => void
  export const connectCreateSdfTexture: (
    createSdfTexture: () => number,
    createComputeDepthTexture: (width: number, height: number) => number
  ) => void
  export const connectCacheCallbacks: (
    create_cache_texture: () => number,
    start_cache: (texture_id: number, box: zig.BoundingBox, width: number, height: number) => void,
    end_cache: VoidFunction
  ) => void
  export const connectSelectedAssetUpdates: (
    on_selected_asset_update: (bounds: zig.PointUV[] | null, props: zig.ShapeProps | null) => void
  ) => void
  export const connectTyping: (
    enable: (text: string) => void,
    disable: VoidFunction,
    updateContent: (text: string) => void,
    updateSelection: (start: number, end: number) => void,
    getCharData: (font_id: number, char_code: number) => SerializedCharDetails,
    getKerning: (font_id: number, char_code_a: number, char_code_b: number) => number
  ) => void
  export const setCaretPosition: (selection_start: number, selection_end: number) => void

  export const tick: (time: DOMHighResTimeStamp) => void
  export const computeSdfs: VoidFunction
  export const renderDraw: (is_ui_hidden: boolean) => void
  export const renderPick: VoidFunction
  export const deinitState: VoidFunction
  export const setTool: (tool: number) => void

  export const importUiElement: (
    id: UiElementType,
    paths: zig.Point[][],
    sdf_texture_id: number
  ) => void
  export const generateUiElementsSdf: VoidFunction

  export const toggleSharedTextEffects: VoidFunction
  export const setSelectedAssetProps: (props: Partial<zig.ShapeProps>) => void
  export const setSelectedAssetBounds: (bounds: zig.PointUV[]) => void
  export const updateProjectSize: (width: number, height: number) => void
}
