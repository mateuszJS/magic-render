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

type ZigF32Array = { typedArray: Float32Array }
type ZigAssetInput = {
  id: number
  points: PointUV[]
  texture_id: number
}
type ZigAssetOutput = {
  id: number
  points: PointUV[]
  texture_id: number
}
type ArrayPointerDataView = {
  '*': PointerDataView
}
type PointerDataView = {
  dataView: DataView
}

declare module '*.zig' {
  export const init_state: (width: number, height: number) => void
  export const add_asset: (maybe_asset_id: number, points: PointUV[], texture_id: number) => void
  export const remove_asset: () => void
  export const reset_assets: (assets: ZigAssetInput[], with_snapshot: boolean) => void

  export const init_svg_textures: (
    texture_max_size: number,
    resize_texture: (texture_id: number, width: number, height: number) => void
  ) => void

  export const add_svg_texture: (texture_id: number, width: number, height: number) => void

  export const on_update_pick: (id: number) => void
  export const on_pointer_down: (x: number, y: number) => void
  export const on_pointer_up: () => void
  export const on_pointer_move: (x: number, y: number) => void
  export const on_pointer_leave: VoidFunction
  export const commitChanges: VoidFunction
  export const update_render_scale: (render_scale: number) => void

  export const connect_web_gpu_programs: (programs: {
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
  export const connect_on_asset_update_callback: (cb: (data: ZigAssetOutput[]) => void) => void
  export const connect_on_asset_selection_callback: (cb: (data: number) => void) => void
  export const connect_cache_callbacks: (
    start_cache: (texture_id: number | null, box: BoundingBox) => number,
    end_cache: VoidFunction
  ) => void

  export const render_draw: VoidFunction
  export const render_pick: VoidFunction
  export const destroy_state: VoidFunction
  export const set_tool: (tool: number) => void

  export const import_icons: (data: number[]) => void
}
