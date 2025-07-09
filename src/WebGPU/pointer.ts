import { on_pointer_move, on_pointer_down, on_pointer_up } from '../logic/index.zig'

export const pointer = {
  x: 0,
  y: 0,
  afterPickEventsQueue: [] as Array<{ requireNewPick: boolean; cb: VoidFunction }>,
}

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
    const move = () => {
      updatePointer(e)
      on_pointer_move(pointer.x, canvas.height - pointer.y)
    }
    if (pointer.afterPickEventsQueue.length > 0) {
      pointer.afterPickEventsQueue.push({
        requireNewPick: false,
        cb: move,
      })
    } else {
      move()
    }
  })

  canvas.addEventListener('mousedown', (e) => {
    updatePointer(e)
    pointer.afterPickEventsQueue.push({
      requireNewPick: true,
      cb: on_pointer_down.bind(null, pointer.x, canvas.height - pointer.y),
    })
  })

  canvas.addEventListener('mouseup', () => {
    if (pointer.afterPickEventsQueue.length > 0) {
      pointer.afterPickEventsQueue.push({
        requireNewPick: false,
        cb: on_pointer_up,
      })
    } else {
      on_pointer_up()
    }
  })

  canvas.addEventListener('wheel', (event) => {
    console.log(event.deltaY)
  })
}
