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

declare module '*.zig' {
  export const init_state: (width: number, height: number) => void
  export const add_asset: (maybe_asset_id: number, points: PointUV[], texture_id: number) => void
  export const remove_asset: () => void
  export const reset_assets: (assets: ZigAssetInput[], with_snapshot: boolean) => void

  export const on_update_pick: (id: number) => void
  export const on_pointer_down: (x: number, y: number) => void
  export const on_pointer_up: () => void
  export const on_pointer_move: (x: number, y: number) => void
  export const on_pointer_leave: VoidFunction

  export const connect_web_gpu_programs: (programs: {
    draw_texture: (vertexData: ZigF32Array, texture_id: number) => void
    draw_triangle: (vertexData: ZigF32Array) => void
    draw_msdf: (vertexData: ZigF32Array, texture_id: number) => void
    pick_texture: (vertexData: ZigF32Array, texture_id: number) => void
    pick_triangle: (vertexData: ZigF32Array) => void
  }) => void
  export const connect_on_asset_update_callback: (cb: (data: ZigAssetOutput[]) => void) => void
  export const connect_on_asset_selection_callback: (cb: (data: number) => void) => void

  export const canvas_render: VoidFunction
  export const picks_render: VoidFunction
  export const destroy_state: VoidFunction

  export const import_icons: (data: number[]) => void
}
