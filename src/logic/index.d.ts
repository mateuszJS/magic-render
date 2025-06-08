interface PointUV {
  x: number
  y: number
  u: number
  v: number
}

type ZigF32Array = { typedArray: Float32Array }
type Texture = {
  id: number
  points: PointUV[]
  texture_id: number
}

declare module '*.zig' {
  export const ASSET_ID_TRESHOLD: number
  export const init_state: (width: number, height: number) => void
  export const add_texture: (id: number, points: PointUV[], textre_index: number) => void
  export const update_points: (id: number, points: PointUV[]) => void

  export const on_update_pick: (id: number) => void
  export const on_pointer_click: () => void
  export const on_pointer_down: (x: number, y: number) => void
  export const on_pointer_up: () => void
  export const on_pointer_move: (x: number, y: number) => void

  export const connectWebGPUPrograms: (programs: {
    draw_texture: (vertexData: ZigF32Array, texture_id: number) => void
    draw_triangle: (vertexData: ZigF32Array) => void
    pick_texture: (vertexData: ZigF32Array, texture_id: number) => void
  }) => void
  export const connectOnAssetUpdateCallback: (cb: (data: Texture[]) => void) => void

  export const canvas_render: VoidFunction
  export const picks_render: VoidFunction
}
