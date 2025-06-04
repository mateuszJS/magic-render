// import type { State } from "../../crate/glue_code"
import { on_pointer_move, on_pointer_click, on_pointer_down, on_pointer_up } from "../logic/index.zig"

export const pointer = { x: 0, y: 0 }


export default function initMouseController(canvas: HTMLCanvasElement, /*state: State*/) {
  pointer.x = 0
  pointer.y = 0


function updatePointer(e: MouseEvent) {
  const rect = canvas.getBoundingClientRect()
  pointer.x = e.clientX - rect.left
  pointer.y = e.clientY - rect.top
}

  canvas.addEventListener('mouseleave', () => {
  })

  canvas.addEventListener('mousemove', e => {
    updatePointer(e)
    on_pointer_move(pointer.x, pointer.y)
  })

  canvas.addEventListener('click', e => {
    on_pointer_click()
  })

  canvas.addEventListener('mousedown', e => {
    updatePointer(e)
    on_pointer_down(pointer.x, pointer.y)
  })

  canvas.addEventListener('mouseup', e => {
    on_pointer_up()
  })

  canvas.addEventListener("wheel", (event) => {
    console.log(event.deltaY)
  })
}