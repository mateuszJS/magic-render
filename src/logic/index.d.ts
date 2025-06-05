interface PointUV {
  x: number
  y: number
  u: number
  v: number
}

declare module "*.zig" {
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
    draw_texture: (vertexData: Float32Array, texture_id: number) => void
    draw_triangle: (vertexData: Float32Array) => void
    pick_texture: (vertexData: Float32Array, texture_id: number) => void
  }) => void
  export const canvas_render: VoidFunction
  export const picks_render: VoidFunction
}