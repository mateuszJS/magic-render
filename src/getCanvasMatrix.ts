import mat4 from 'utils/mat4'

export default function getCanvasMatrix(canvas: HTMLCanvasElement) {
  const matrix = mat4.ortho(
    0, // left
    canvas.clientWidth, // right
    0, // bottom
    canvas.clientHeight, // top
    1, // near
    -1 // far
  )

  return matrix
}
