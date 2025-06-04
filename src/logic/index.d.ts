interface PointUV {
  x: number
  y: number
  u: number
  v: number
}

declare module "*.zig" {
  export const init_state: (width: number, height: number) => void
  export const add_texture: (id: number, points: PointUV[], textre_index: number) => void
  export const get_shader_input: (id: number) => { texture_id: number, vertex_data: number[] }
  export const get_shader_pick_input: (id: number) => { texture_id: number, vertex_data: number[] }
  export const update_points: (id: number, points: PointUV[]) => void
  export const on_update_pick: (id: number) => void
  export const on_pointer_click: () => void
  export const on_pointer_down: (x: number, y: number) => void
  export const on_pointer_up: () => void
  export const on_pointer_move: (x: number, y: number) => void
  export const get_border: () => number[]
  export const main: () => void
}