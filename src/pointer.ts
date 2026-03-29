import * as Logic from 'logic/index.zig'
import clamp from './utils/clamp'
import * as Typing from './typing'
import { Point } from 'types'

const OUTSIDE_CANVAS = -1

enum MouseMode {
  Pan,
  Zoom,
  None,
}

let mouseMode = MouseMode.None
let panCameraStart: Point | null = null

export function getWorldPointer(canvasHeight: number): [number, number] {
  return [
    (pointer.x - camera.x) / camera.zoom, //
    (canvasHeight - pointer.y - camera.y) / camera.zoom,
  ]
}

export const camera = {
  x: 0,
  y: 0,
  zoom: 1,
  redrawNeeded: true,
}

export const pointer = {
  x: 0,
  y: 0,
  afterPickEventsQueue: [] as Array<{ requireNewPick: boolean; cb: VoidFunction }>,
  /* this queue exists because when mobile device is touched we have to:
    1) update pointer,
    2) do picking,
    3) record a click in order,
    so click has to wait after pick is done
  But it's also useful for fast "unit" testing */
}

export default function initMouseController(
  canvas: HTMLCanvasElement,
  onZoom: VoidFunction,
  onStartProcessing: VoidFunction,
  abortSignal: AbortSignal
) {
  pointer.x = OUTSIDE_CANVAS
  pointer.y = OUTSIDE_CANVAS

  const eventOptions: AddEventListenerOptions = {
    signal: abortSignal,
  }

  function updatePointer(e: MouseEvent | Touch) {
    const rect = canvas.getBoundingClientRect()
    const scale = canvas.width / rect.width
    pointer.x = (e.clientX - rect.left) * scale
    pointer.y = (e.clientY - rect.top) * scale
  }

  function getTouchDistance(t1: Touch, t2: Touch) {
    return Math.hypot(t1.clientX - t2.clientX, t1.clientY - t2.clientY)
  }

  canvas.addEventListener(
    'mouseleave',
    () => {
      onStartProcessing()
      canvas.style.cursor = 'default'

      const update = () => {
        pointer.x = OUTSIDE_CANVAS
        pointer.y = OUTSIDE_CANVAS
        Logic.onPointerLeave()
      }
      pointer.afterPickEventsQueue.push({
        requireNewPick: false,
        cb: update,
      })
    },
    eventOptions
  )

  canvas.addEventListener(
    'dblclick',
    () => {
      Logic.onPointerDoubleClick()
    },
    eventOptions
  )

  canvas.addEventListener(
    'mousemove',
    (e) => {
      if (panCameraStart) {
        updatePointer(e)

        camera.x = pointer.x - panCameraStart.x
        camera.y = -(pointer.y - panCameraStart.y)
        camera.redrawNeeded = true
        return
      }

      onPointerMove(e)
    },
    eventOptions
  )

  const onPointerMove = (e: MouseEvent | Touch) => {
    onStartProcessing()
    const move = () => {
      updatePointer(e)
      Logic.onPointerMove(
        ...getWorldPointer(canvas.height),
        e instanceof MouseEvent ? e.shiftKey : false,
        e instanceof MouseEvent ? e.ctrlKey || e.metaKey || e.altKey : false
      )
    }
    pointer.afterPickEventsQueue.push({
      requireNewPick: false,
      cb: move,
    })
  }

  let isPointerDown = false /* to avoid triggering pointer up when user click outside of canvas,
  moves mouse and does "pointer up" event on the canvas. For example when user want to selct contenr of
  the text area, and moved pointer up to the canvas. IF "poitner up" event will fire,
  then selected element will be unselected, and possible that text area will also dissapear */

  const onPointerDown = (e: MouseEvent | Touch) => {
    onStartProcessing()
    updatePointer(e)
    isPointerDown = true
    pointer.afterPickEventsQueue.push({
      requireNewPick: true,
      cb: Logic.onPointerDown.bind(null, ...getWorldPointer(canvas.height)),
    })
  }

  const onPointerUp = () => {
    if (!isPointerDown) return

    onStartProcessing()
    isPointerDown = false

    pointer.afterPickEventsQueue.push({
      requireNewPick: false,
      cb: Logic.onPointerUp,
    })
  }

  canvas.addEventListener(
    'mousedown',
    (e) => {
      if (mouseMode === MouseMode.Pan) {
        updatePointer(e)
        panCameraStart = {
          x: pointer.x - camera.x,
          y: pointer.y + camera.y,
        }
        canvas.style.cursor = 'grabbing'
        return
      }
      panCameraStart = null

      onPointerDown(e)
    },
    eventOptions
  )

  canvas.addEventListener(
    'mouseup',
    () => {
      mouseMode = MouseMode.None
      panCameraStart = null
      canvas.style.cursor = 'default'

      onPointerUp()
    },
    eventOptions
  )

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

  function wheelZoom(delta: number) {
    const oldZoom = camera.zoom
    camera.zoom = clamp(camera.zoom - delta * 0.005, 0.1, 20)
    onZoom()
    const zoomFactor = camera.zoom / oldZoom
    camera.x = pointer.x - (pointer.x - camera.x) * zoomFactor
    const realY = canvas.height - pointer.y
    camera.y = realY - (realY - camera.y) * zoomFactor
    camera.redrawNeeded = true
  }

  /* panning , supports both scroll and touch, expect Safari */
  canvas.addEventListener(
    'wheel',
    (event) => {
      updatePointer(event)
      event.preventDefault()
      if (mouseMode === MouseMode.Zoom) {
        const delta = Math.abs(event.deltaY) > Math.abs(event.deltaX) ? event.deltaY : -event.deltaX
        wheelZoom(delta)
      } else {
        if (event.ctrlKey) {
          wheelZoom(event.deltaY * camera.zoom)
        } else {
          camera.x -= event.deltaX
          camera.y += event.deltaY
          camera.redrawNeeded = true
        }
      }
    },
    eventOptions
  )
  // pointer.zoom = clamp(pointer.zoom + event.deltaY * 0.01, 0.1, 100)
  // add abort signal to key's events
  document.body.addEventListener(
    'keydown',
    (event) => {
      const notTypingKeys = event.ctrlKey || event.code === 'AltLeft' || event.code === 'AltRight'
      if (Typing.isEnabled() && !notTypingKeys) return

      const isInputFocused =
        document.activeElement?.tagName === 'INPUT' ||
        document.activeElement?.tagName === 'TEXTAREA'

      switch (event.key) {
        case ' ':
          if (isInputFocused) return

          if (mouseMode !== MouseMode.Pan) {
            canvas.style.cursor = 'grab'
            mouseMode = MouseMode.Pan
          }
          break
        case 'Alt':
          mouseMode = MouseMode.Zoom
          break
        case 'Escape':
          Logic.commitChanges()
          break
        case '=':
          // case '+':
          // Zoom in with Ctrl/Cmd + Plus

          if (isInputFocused) return

          if (event.ctrlKey || event.metaKey) {
            event.preventDefault()
            const centerX = pointer.x !== OUTSIDE_CANVAS ? pointer.x : canvas.width / 2
            const centerY = pointer.y !== OUTSIDE_CANVAS ? pointer.y : canvas.height / 2
            performZoom(0.1, centerX, centerY)
          }
          break
        case '-':
          // case '_':
          // Zoom out with Ctrl/Cmd/Shift + Minus

          if (isInputFocused) return

          if (event.ctrlKey || event.metaKey || event.shiftKey) {
            event.preventDefault()
            const centerX = pointer.x !== OUTSIDE_CANVAS ? pointer.x : canvas.width / 2
            const centerY = pointer.y !== OUTSIDE_CANVAS ? pointer.y : canvas.height / 2
            performZoom(-0.1, centerX, centerY)
          }
          break
        case 'Delete':
        case 'Backspace':
          Logic.removeAsset()
          break
        case 'Meta': {
          // update the way transform works
        }
      }
    },
    eventOptions
  )

  document.body.addEventListener(
    'keyup',
    (event) => {
      if (event.key === ' ' || event.key === 'Alt') {
        mouseMode = MouseMode.None
      }
      if (event.key === ' ' && panCameraStart === null) {
        canvas.style.cursor = 'default'
      }
    },
    eventOptions
  )

  const touchEventOptions: AddEventListenerOptions = {
    passive: false,
    signal: abortSignal,
  }

  let lastTouchDistance = 0
  let lastTouchMidpoint: Point | null = null

  // useful for detectign double click on touch devices
  let lastTapTime = 0
  let lastTapX = 0
  let lastTapY = 0

  canvas.addEventListener(
    'touchstart',
    (e) => {
      e.preventDefault()

      if (e.touches.length === 1) {
        onPointerDown(e.touches[0])
      } else if (e.touches.length === 2) {
        lastTouchDistance = getTouchDistance(e.touches[0], e.touches[1])
        lastTouchMidpoint = {
          x: (e.touches[0].clientX + e.touches[1].clientX) / 2,
          y: (e.touches[0].clientY + e.touches[1].clientY) / 2,
        }
        // Cancel any ongoing single-touch drawing operation
        onPointerUp()
      }
    },
    touchEventOptions
  )

  canvas.addEventListener(
    'touchmove',
    (e) => {
      e.preventDefault()

      if (e.touches.length === 1) {
        onStartProcessing()
        onPointerMove(e.touches[0])
      } else if (e.touches.length === 2) {
        const t1 = e.touches[0]
        const t2 = e.touches[1]
        const newDistance = getTouchDistance(t1, t2)
        const midClientX = (t1.clientX + t2.clientX) / 2
        const midClientY = (t1.clientY + t2.clientY) / 2

        const rect = canvas.getBoundingClientRect()
        const scale = canvas.width / rect.width
        const midX = (midClientX - rect.left) * scale
        const midY = (midClientY - rect.top) * scale

        if (lastTouchDistance > 0) {
          console.log(newDistance - lastTouchDistance)
          performZoom((newDistance - lastTouchDistance) * 0.003 * camera.zoom, midX, midY)
        }

        if (lastTouchMidpoint) {
          camera.x += (midClientX - lastTouchMidpoint.x) * scale
          camera.y -= (midClientY - lastTouchMidpoint.y) * scale
          camera.redrawNeeded = true
        }

        lastTouchDistance = newDistance
        lastTouchMidpoint = { x: midClientX, y: midClientY }
      }
    },
    touchEventOptions
  )

  function handleTouchEnd(e: TouchEvent) {
    e.preventDefault()

    if (e.touches.length === 0) {
      onPointerUp()

      if (e.changedTouches.length === 1) {
        const touch = e.changedTouches[0]
        const now = Date.now()
        const dx = touch.clientX - lastTapX
        const dy = touch.clientY - lastTapY
        const isDoubleTap = now - lastTapTime < 300 && Math.hypot(dx, dy) < 30
        if (isDoubleTap) {
          Logic.onPointerDoubleClick()
          lastTapTime = 0
        } else {
          lastTapTime = now
          lastTapX = touch.clientX
          lastTapY = touch.clientY
        }
      }
    }

    if (e.touches.length < 2) {
      lastTouchDistance = 0
      lastTouchMidpoint = null
    }
  }

  canvas.addEventListener('touchend', handleTouchEnd, touchEventOptions)
  canvas.addEventListener('touchcancel', handleTouchEnd, touchEventOptions)
}
