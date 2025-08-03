import {
  on_pointer_move,
  on_pointer_leave,
  on_pointer_down,
  on_pointer_up,
} from '../logic/index.zig'
import clamp from '../utils/clamp'

const OUTSIDE_CANVAS = -1

enum CameraMode {
  Pan,
  Zoom,
  None,
}

let cameraMode = CameraMode.None
let panCameraStart: Point | null = null

export const camera = {
  x: 0,
  y: 0,
  zoom: 1,
}

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
  onZoom: VoidFunction,
  onStartProcessing: VoidFunction
) {
  pointer.x = OUTSIDE_CANVAS
  pointer.y = OUTSIDE_CANVAS

  function getZigAbsolutePointer(): [number, number] {
    return [
      (pointer.x - camera.x) / camera.zoom,
      (canvas.height - pointer.y - camera.y) / camera.zoom,
    ]
  }

  function updatePointer(e: MouseEvent) {
    const rect = canvas.getBoundingClientRect()
    const scale = canvas.width / rect.width
    pointer.x = (e.clientX - rect.left) * scale
    pointer.y = (e.clientY - rect.top) * scale
  }

  canvas.addEventListener('mouseleave', () => {
    onStartProcessing()
    canvas.style.cursor = 'default'

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
    if (panCameraStart) {
      updatePointer(e)

      camera.x = pointer.x - panCameraStart.x
      camera.y = -(pointer.y - panCameraStart.y)
      return
    }

    onStartProcessing()

    const move = () => {
      updatePointer(e)
      on_pointer_move(...getZigAbsolutePointer())
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
    if (cameraMode === CameraMode.Pan) {
      updatePointer(e)
      panCameraStart = {
        x: pointer.x - camera.x,
        y: pointer.y + camera.y,
      }
      canvas.style.cursor = 'grabbing'
      return
    }
    panCameraStart = null

    onStartProcessing()

    updatePointer(e)
    pointer.afterPickEventsQueue.push({
      requireNewPick: true,
      cb: on_pointer_down.bind(null, ...getZigAbsolutePointer()),
    })
  })

  canvas.addEventListener('mouseup', () => {
    cameraMode = CameraMode.None
    panCameraStart = null
    canvas.style.cursor = 'default'

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

  /* zoom functionality shared between wheel and keyboard */
  function performZoom(zoomDelta: number, centerX: number, centerY: number) {
    const oldZoom = camera.zoom
    camera.zoom = clamp(camera.zoom + zoomDelta, 0.1, 20)
    onZoom()

    const zoomFactor = camera.zoom / oldZoom

    camera.x = centerX - (centerX - camera.x) * zoomFactor
    const realY = canvas.height - centerY
    camera.y = realY - (realY - camera.y) * zoomFactor
  }

  /* panning , supports both scroll and touch, expect Safari */
  canvas.addEventListener('wheel', (event) => {
    event.preventDefault()
    if (cameraMode === CameraMode.Zoom) {
      performZoom(-event.deltaY * 0.005, pointer.x, pointer.y)
    } else {
      camera.x -= event.deltaX
      camera.y += event.deltaY
    }
  })
  // pointer.zoom = clamp(pointer.zoom + event.deltaY * 0.01, 0.1, 100)

  document.body.addEventListener('keydown', (event) => {
    if (event.code === 'Space') {
      event.preventDefault()
      if (cameraMode !== CameraMode.Pan) {
        canvas.style.cursor = 'grab'
        cameraMode = CameraMode.Pan
      }
    } else if (event.key === 'Alt') {
      event.preventDefault()
      cameraMode = CameraMode.Zoom
    } else if ((event.ctrlKey || event.metaKey) && (event.key === '=' || event.key === '+')) {
      // Zoom in with Ctrl/Cmd + Plus
      event.preventDefault()
      const centerX = pointer.x !== OUTSIDE_CANVAS ? pointer.x : canvas.width / 2
      const centerY = pointer.y !== OUTSIDE_CANVAS ? pointer.y : canvas.height / 2
      performZoom(0.1, centerX, centerY)
    } else if ((event.ctrlKey || event.metaKey || event.shiftKey) && event.key === '-') {
      // Zoom out with Ctrl/Cmd/Shift + Minus
      event.preventDefault()
      const centerX = pointer.x !== OUTSIDE_CANVAS ? pointer.x : canvas.width / 2
      const centerY = pointer.y !== OUTSIDE_CANVAS ? pointer.y : canvas.height / 2
      performZoom(-0.1, centerX, centerY)
    }
  })
  document.body.addEventListener('keyup', (event) => {
    if (event.code === 'Space' || event.key === 'Alt') {
      cameraMode = CameraMode.None
    }
    if (event.code === 'Space' && panCameraStart === null) {
      canvas.style.cursor = 'default'
    }
  })

  let lastTouchY: number

  canvas.addEventListener('touchstart', (event) => {
    if (event.touches.length === 2) {
      event.preventDefault()

      lastTouchY = event.touches[0].clientY
    }
  })

  canvas.addEventListener('touchmove', (event) => {
    if (event.touches.length === 2) {
      event.preventDefault()

      const delta = lastTouchY - event.touches[0].clientY
      lastTouchY = event.touches[0].clientY

      camera.zoom = clamp(camera.zoom - delta * 0.01, 0.1, 20)
      onZoom()
    }
  })
}
