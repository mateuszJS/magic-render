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
  onStartProcessing: VoidFunction,
  abortSignal: AbortSignal
) {
  pointer.x = OUTSIDE_CANVAS
  pointer.y = OUTSIDE_CANVAS

  const eventOptions: AddEventListenerOptions = {
    signal: abortSignal,
  }

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
      if (pointer.afterPickEventsQueue.length > 0) {
        pointer.afterPickEventsQueue.push({
          requireNewPick: false,
          cb: update,
        })
      } else {
        update()
      }
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
        return
      }

      onStartProcessing()

      const move = () => {
        updatePointer(e)
        Logic.onPointerMove(...getZigAbsolutePointer())
      }
      if (pointer.afterPickEventsQueue.length > 0) {
        pointer.afterPickEventsQueue.push({
          requireNewPick: false,
          cb: move,
        })
      } else {
        move()
      }
    },
    eventOptions
  )

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

      onStartProcessing()

      updatePointer(e)
      pointer.afterPickEventsQueue.push({
        requireNewPick: true,
        cb: Logic.onPointerDown.bind(null, ...getZigAbsolutePointer()),
      })
    },
    eventOptions
  )

  canvas.addEventListener(
    'mouseup',
    () => {
      mouseMode = MouseMode.None
      panCameraStart = null
      canvas.style.cursor = 'default'

      onStartProcessing()

      if (pointer.afterPickEventsQueue.length > 0) {
        pointer.afterPickEventsQueue.push({
          requireNewPick: false,
          cb: Logic.onPointerUp,
        })
      } else {
        Logic.onPointerUp()
      }
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

  // The code below is from mozzila MDN docs, and it's a good base once we can test on mobile

  // function updateBackground(ev: TouchEvent) {
  //   switch (ev.targetTouches.length) {
  //     case 1:
  //       console.log('single tap')
  //       break
  //     case 2:
  //       console.log('Two simultaneous touches')
  //       break
  //     default:
  //       console.log('More than two simultaneous touches')
  //   }
  // }

  // const tpCache: Touch[] = []

  // canvas.addEventListener('touchstart', (event) => {
  //   // If the user makes simultaneous touches, the browser will fire a
  //   // separate touchstart event for each touch point. Thus if there are
  //   // three simultaneous touches, the first touchstart event will have
  //   // targetTouches length of one, the second event will have a length
  //   // of two, and so on.
  //   console.log(event.targetTouches.length)
  //   event.preventDefault()
  //   // Cache the touch points for later processing of 2-touch pinch/zoom
  //   if (event.targetTouches.length === 2) {
  //     for (const touch of event.targetTouches) {
  //       tpCache.push(touch)
  //     }
  //   }
  //   // if (logEvents) log('touchStart', event, true)
  //   updateBackground(event)
  // })

  // canvas.addEventListener('touchmove', (ev) => {
  //   // Note: if the user makes more than one "simultaneous" touches, most browsers
  //   // fire at least one touchmove event and some will fire several touch moves.
  //   // Consequently, an application might want to "ignore" some touch moves.
  //   //
  //   // This function sets the target element's border to "dashed" to visually
  //   // indicate the target received a move event.
  //   //
  //   ev.preventDefault()
  //   // if (logEvents) log('touchMove', ev, false)
  //   // To avoid too much color flashing many touchmove events are started,
  //   // don't update the background if two touch points are active
  //   if (!(ev.touches.length === 2 && ev.targetTouches.length === 2)) updateBackground(ev)

  //   // Set the target element's border to dashed to give a clear visual
  //   // indication the element received a move event.
  //   // ev.target.style.border = 'dashed'

  //   // Check this event for 2-touch Move/Pinch/Zoom gesture
  //   handlePinchZoom(ev)
  // })

  // function handlePinchZoom(ev: TouchEvent) {
  //   if (ev.targetTouches.length === 2 && ev.changedTouches.length === 2) {
  //     // Check if the two target touches are the same ones that started
  //     // the 2-touch
  //     const reverseTpCache = tpCache.slice().reverse()
  //     const point1 = reverseTpCache.findIndex(
  //       (tp) => tp.identifier === ev.targetTouches[0].identifier
  //     )
  //     const point2 = reverseTpCache.findIndex(
  //       (tp) => tp.identifier === ev.targetTouches[1].identifier
  //     )

  //     if (point1 >= 0 && point2 >= 0) {
  //       // Calculate the difference between the start and move coordinates
  //       const diff1 = Math.abs(tpCache[point1].clientX - ev.targetTouches[0].clientX)
  //       const diff2 = Math.abs(tpCache[point2].clientX - ev.targetTouches[1].clientX)

  //       // This threshold is device dependent as well as application specific
  //       const PINCH_THRESHOLD = (ev.target as HTMLCanvasElement).clientWidth / 10
  //       if (diff1 >= PINCH_THRESHOLD && diff2 >= PINCH_THRESHOLD) {
  //         // ev.target.style.background = 'green'
  //         console.log('Pinch zoom detected')
  //       }
  //     } else {
  //       // empty tpCache
  //       tpCache.length = 0
  //     }
  //   }
  // }

  // function endHandler(ev: TouchEvent) {
  //   ev.preventDefault()
  //   // if (logEvents) log(ev.type, ev, false)
  //   if (ev.targetTouches.length === 0) {
  //     // Restore background and border to original values
  //     // ev.target.style.background = 'white'
  //     // ev.target.style.border = '1px solid black'
  //   }
  // }

  // canvas.addEventListener('touchcancel', endHandler)
  // canvas.addEventListener('touchend', endHandler)
}
