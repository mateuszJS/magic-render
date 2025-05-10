export const pointer = { x: 0, y: 0 }

export default function initMouseController(canvas: HTMLCanvasElement) {
  pointer.x = 0
  pointer.y = 0

  canvas.addEventListener('mouseleave', () => {
  })

  canvas.addEventListener('mousemove', e => {
    pointer.x = e.clientX
    pointer.y = e.clientY
  })

  canvas.addEventListener('mousedown', e => {

  })

  canvas.addEventListener('mouseup', e => {

  })

  canvas.addEventListener("wheel", (event) => {
    console.log(event.deltaY)
  })
}