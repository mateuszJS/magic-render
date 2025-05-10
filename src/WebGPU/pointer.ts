export const pointer = { x: 0, y: 0 }

export default function initMouseController(canvas: HTMLCanvasElement) {
  pointer.x = 0
  pointer.y = 0

  canvas.addEventListener('mouseleave', () => {
  })

  canvas.addEventListener('mousemove', e => {
    const rect = canvas.getBoundingClientRect()
    pointer.x = e.clientX - rect.left
    pointer.y = e.clientY - rect.top
  })

  canvas.addEventListener('mousedown', e => {

  })

  canvas.addEventListener('mouseup', e => {

  })

  canvas.addEventListener("wheel", (event) => {
    console.log(event.deltaY)
  })
}