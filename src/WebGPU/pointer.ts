import { on_pointer_move, on_pointer_down, on_pointer_up } from '../logic/index.zig'

export const pointer = { x: 0, y: 0 }

export default function initMouseController(canvas: HTMLCanvasElement) {
  pointer.x = 0
  pointer.y = 0

  function updatePointer(e: MouseEvent) {
    const rect = canvas.getBoundingClientRect()
    pointer.x = e.clientX - rect.left
    pointer.y = e.clientY - rect.top
  }

  canvas.addEventListener('mouseleave', () => {})

  canvas.addEventListener('mousemove', (e) => {
    updatePointer(e)
    on_pointer_move(pointer.x, canvas.height - pointer.y)
  })

  canvas.addEventListener('mousedown', () => {
    on_pointer_down(pointer.x, canvas.height - pointer.y)
  })

  canvas.addEventListener('mouseup', () => {
    on_pointer_up()
  })

  canvas.addEventListener('wheel', (event) => {
    console.log(event.deltaY)
  })
}
