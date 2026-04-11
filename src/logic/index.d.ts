// types below does not need to be exported from this package
type UiElementType = 0

type ArrayPointerDataView = {
  '*': PointerDataView
}
type PointerDataView = {
  dataView: DataView<ArrayBuffer>
}

type ShapeDrawUniform = OneOf<{
  solid: PointerDataView
  linear: PointerDataView
  radial: PointerDataView
  program: PointerDataView
}>

declare module '*.zig' {
  import {
    Point,
    PointUV,
    Id,
    ZigProjectSnapshot,
    TypoProps,
    BasicProps,
    ZigEffect,
    BoundingBox,
  } from 'types'

  export const initState: (
    width: number,
    height: number,
    max_texture_size: number,
    max_buffer_size: number,
    isTest: boolean
  ) => void
  export const updateCache: VoidFunction
  export const removeAsset: () => void
  export const setSnapshot: (snapshot: ZigProjectSnapshot, with_snapshot: boolean) => void

  export const onUpdatePick: (id: Id) => void
  export const onPointerDown: (x: number, y: number) => void
  export const onPointerUp: () => void
  export const onPointerMove: (
    x: number,
    y: number,
    constrained: boolean,
    maintain_center: boolean
  ) => void
  export const onPointerDoubleClick: VoidFunction
  export const onPointerLeave: VoidFunction
  export const commitChanges: VoidFunction
  export const updateRenderScale: (zoom: number, pixel_density: number) => void
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
    start_combine_sdf: (
      sdfTextureId: number,
      computeDepthTextureId: number,
      width: number,
      height: number
    ) => void
    combine_sdf: (
      destinationTexId: number,
      sourceTexId: number,
      computeDepthTextureId: number,
      uniformData: PointerDataView,
      curves_data: ArrayPointerDataView
    ) => void
    finish_combine_sdf: () => void
    draw_shape: (
      bound_box_data: ArrayPointerDataView,
      uniformData: ShapeDrawUniform,
      sdf_texture_id: number,
      curves_data: ArrayPointerDataView,
      uniform_t: ArrayPointerDataView
    ) => void
    pick_shape: (
      bound_box_data: ArrayPointerDataView,
      uniformData: PointerDataView,
      sdf_texture_id: number,
      curves_data: ArrayPointerDataView,
      uniform_t: ArrayPointerDataView
    ) => void
  }) => void
  export function glueJsGeneral(
    onAssetUpdate: (snapshot: ZigProjectSnapshot, commit: boolean) => void,
    onAssetSelection: (data: Id) => void,
    onUpdateTool: (new_tool: number) => void,
    createSdfTexture: () => number,
    createDisposableComputeDepthTexture: (width: number, height: number) => number,
    getCharData: (font_id: number, char_code: number) => SerializedCharDetails,
    getKerning: (font_id: number, char_code_a: number, char_code_b: number) => number
  ): void

  export function glueJsTextureCache(
    createCacheTexture: () => number,
    startCache: (texture_id: number, box: BoundingBox, width: number, height: number) => void,
    endCache: VoidFunction
  ): void

  export const connectTyping: (
    enable: (text: string) => void,
    disable: VoidFunction,
    updateContent: (text: string) => void,
    updateSelection: (start: number, end: number) => void
  ) => void
  export const setCaretPosition: (selection_start: number, selection_end: number) => void

  export const tick: (time: DOMHighResTimeStamp) => boolean
  export const computePhase: VoidFunction
  export const renderDraw: (is_ui_hidden: boolean) => void
  export const renderPick: VoidFunction
  export const deinitState: VoidFunction
  export const setTool: (tool: number) => void
  export const addText: VoidFunction

  export const importUiElement: (
    id: UiElementType,
    paths: Point[][],
    sdf_texture_id: number
  ) => void
  export const generateUiElementsSdf: VoidFunction

  export const setSelectedAssetBounds: (bounds: PointUV[], commit: boolean) => void
  export const setSelectedAssetProps: (props: BasicProps, commit: boolean) => void
  export const setSelectedAssetEffects: (effects: ZigEffect[], commit: boolean) => void
  export const setSelectedAssetTypoProps: (typo_props: TypoProps, commit: boolean) => void

  export const addFont: (font_id: number) => void
  export const onBlurTextArea: VoidFunction

  export const INFINITE_DISTANCE: number

  export const invalidateCache: (ids: number[]) => void
}
