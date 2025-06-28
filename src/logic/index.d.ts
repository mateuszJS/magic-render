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
type AssetZig = {
  points: PointUV[]
  texture_id: number
}

declare module '*.zig' {
  export const init_state: (width: number, height: number) => void
  export const add_texture: (points: PointUV[], texture_id: number) => void
  export const update_points: (id: number, points: PointUV[]) => void

  export const on_update_pick: (id: number) => void
  export const on_pointer_down: (x: number, y: number) => void
  export const on_pointer_up: () => void
  export const on_pointer_move: (x: number, y: number) => void

  export const connect_web_gpu_programs: (programs: {
    draw_texture: (vertexData: ZigF32Array, texture_id: number) => void
    draw_triangle: (vertexData: ZigF32Array) => void
    pick_texture: (vertexData: ZigF32Array, texture_id: number) => void
    pick_triangle: (vertexData: ZigF32Array) => void
  }) => void
  export const connect_on_asset_update_callback: (cb: (data: AssetZig[]) => void) => void

  export const canvas_render: VoidFunction
  export const picks_render: VoidFunction
  export const destroy_state: VoidFunction

  export const import_shape: (segments: [Point, Point, Point, Point][]) => void
}
