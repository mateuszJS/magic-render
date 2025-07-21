import {
  on_pointer_move,
  on_pointer_leave,
  on_pointer_down,
  on_pointer_up,
} from '../logic/index.zig'

const OUTSIDE_CANVAS = -1

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
  pointer.x = OUTSIDE_CANVAS
  pointer.y = OUTSIDE_CANVAS

  function updatePointer(e: MouseEvent) {
    const rect = canvas.getBoundingClientRect()
    pointer.x = e.clientX - rect.left
    pointer.y = e.clientY - rect.top
  }

  canvas.addEventListener('mouseleave', () => {
    onStartProcessing()

    const update = () => {
      pointer.x = OUTSIDE_CANVAS
      pointer.y = OUTSIDE_CANVAS
      on_pointer_leave()
    }
    if (pointer.afterPickEventsQueue.length > 0) {
      pointer.afterPickEventsQueue.push({
        requireNewPick: false,
        cb: update,
      })
    } else {
      update()
    }
  })

  canvas.addEventListener('mousemove', (e) => {
    onStartProcessing()

    const move = () => {
      updatePointer(e)
      on_pointer_move(pointer.x, canvas.clientHeight - pointer.y)
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
    onStartProcessing()

    updatePointer(e)
    pointer.afterPickEventsQueue.push({
      requireNewPick: true,
      cb: on_pointer_down.bind(null, pointer.x, canvas.clientHeight - pointer.y),
    })
  })

  canvas.addEventListener('mouseup', () => {
    onStartProcessing()

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
