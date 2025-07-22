import mat4 from 'utils/mat4'
import { camera } from 'WebGPU/pointer'

export default function getCanvasMatrix(canvas: HTMLCanvasElement) {
  const ortho = mat4.ortho(
    0, // left
    canvas.width, // right
    0, // bottom
    canvas.height, // top
    1, // near
    -1 // far
  )
  // when we implement zoom, it might be actually easier to scale our controls/icons down and this matrix up
  // instead of implement zoom for every signle effect I guess
  const translated = mat4.translate(ortho, [camera.x, camera.y, 0])
  const matrix = mat4.scale(translated, [camera.zoom, camera.zoom, 1])

  return matrix
}
