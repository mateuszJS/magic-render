import { on_pointer_move, on_pointer_down, on_pointer_up } from '../logic/index.zig'

export const pointer = {
  x: 0,
  y: 0,
  afterPickEventsQueue: [] as Array<{ requireNewPick: boolean; cb: VoidFunction }>,
  /* this queue exists because wen mobiel device is touched we have to:
    1) update pointer,
    2) do picking,
    3) record a click in order,
    so click has to wait after pick is done */
}

export default function initMouseController(
  canvas: HTMLCanvasElement,
  onStartProcessing: VoidFunction
) {
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
    onStartProcessing()
  })

  canvas.addEventListener('mousedown', (e) => {
    updatePointer(e)
    pointer.afterPickEventsQueue.push({
      requireNewPick: true,
      cb: on_pointer_down.bind(null, pointer.x, canvas.height - pointer.y),
    })
    onStartProcessing()
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
    onStartProcessing()
  })

  canvas.addEventListener('wheel', (event) => {
    console.log(event.deltaY)
  })
}
