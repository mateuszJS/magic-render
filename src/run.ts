import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  generateMSDF,
  pickTexture,
  pickTriangle,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import { canvas_render, picks_render, connect_web_gpu_programs } from 'logic/index.zig'
import { TextureSource } from '.'
import svgToSegments from 'utils/svgToSegments'

const TestShapeSvg = `
<svg viewBox="0 0 100 100" version="1.1" xmlns="http://www.w3.org/2000/svg">
    <path d="M86.467,29.511C82.472,23.734 73.515,15.84 65.626,11.626C53.545,5.174 39.264,3.83 32.01,10.728C19.493,22.63 48.138,36.888 12.048,58.79C-9.698,71.987 26.544,106.787 62.514,97.022C98.483,87.256 99.853,48.867 86.467,29.511Z"/>
</svg>
`
function testSvgToSegments(): number[] {
  const testCanvas = document.createElement('canvas')
  testCanvas.style.position = 'absolute'
  document.body.appendChild(testCanvas)
  testCanvas.width = testCanvas.clientWidth
  testCanvas.height = testCanvas.clientHeight

  const segments = svgToSegments(TestShapeSvg)

  const ctx = testCanvas.getContext('2d')!

  segments.forEach(({ points: [start, cp1, cp2, end] }, i) => {
    ctx.strokeStyle = `rgb(0, ${(i / segments.length) * 255}, 0)`
    ctx.lineWidth = 10
    ctx.beginPath()
    ctx.moveTo(start.x, start.y)
    ctx.bezierCurveTo(
      cp1.x,
      cp1.y,
      (cp2 as Point).x,
      (cp2 as Point).y,
      (end as Point).x,
      (end as Point).y
    )
    ctx.stroke()
  })

  return segments.flatMap((segment) => [
    ...segment.points.flatMap((point) => [point.x, testCanvas.height - point.y]),
    segment.length,
    0, // just a padding to make it vec2f
  ])
}

export const transformMatrix = new Float32Array()
export const MAP_BACKGROUND_SCALE = 1000

export default function runCreator(
  canvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  textures: TextureSource[]
): VoidFunction {
  const canvasMatrix = getCanvasMatrix(canvas)
  let canvasPass: GPURenderPassEncoder

  const pickManager = new PickManager(device)
  let pickMatrix: Float32Array
  let pickPass: GPURenderPassEncoder

  connect_web_gpu_programs({
    draw_texture: (vertex_data, texture_id) =>
      drawTexture(canvasPass, canvasMatrix, vertex_data.typedArray, textures[texture_id].texture),
    draw_triangle: (vertex_data) => drawTriangle(canvasPass, canvasMatrix, vertex_data.typedArray),
    pick_texture: (vertex_data, texture_id) =>
      pickTexture(pickPass, pickMatrix, vertex_data.typedArray, textures[texture_id].texture),
    pick_triangle: (vertex_data) => pickTriangle(pickPass, pickMatrix, vertex_data.typedArray),
  })

  let rafId = 0

  const segments = testSvgToSegments()
  // prettier-ignore
  const vertexData = new Float32Array([
    0, 0, 0, 1,
    canvas.width, canvas.height, 0, 1,
    canvas.width, 0, 0, 1,
    //
    0, 0, 0, 1,
    0, canvas.height, 0, 1,
    canvas.width, canvas.height, 0, 1,
  ])

  let renderAgain = true
  function draw(now: DOMHighResTimeStamp) {
    const encoder = device.createCommandEncoder()

    const canvasDescriptor = getCanvasRenderDescriptor(context, device)
    canvasPass = encoder.beginRenderPass(canvasDescriptor)
    canvas_render()
    generateMSDF(canvasPass, canvasMatrix, vertexData, segments)
    canvasPass.end()

    pickMatrix = pickManager.createMatrix(canvas, canvasMatrix)
    const pick = pickManager.startPicking(encoder)
    pickPass = pick.pass
    picks_render()
    pick.end()

    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])

    pickManager.asyncPick()

    if (renderAgain) {
      renderAgain = false
      rafId = requestAnimationFrame(draw)
    }
  }

  rafId = requestAnimationFrame(draw)

  return () => {
    cancelAnimationFrame(rafId)
  }
}
