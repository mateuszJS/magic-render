import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  drawMSDF,
  pickTexture,
  pickTriangle,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import { canvas_render, picks_render, connect_web_gpu_programs } from 'logic/index.zig'
import { TextureSource } from '.'
import { pointer } from 'WebGPU/pointer'
import getLoadingTexture from 'loadingTexture'

export const transformMatrix = new Float32Array()
export const MAP_BACKGROUND_SCALE = 1000

export default function runCreator(
  canvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  textures: TextureSource[],
  onEmptyEvents: VoidFunction // call when there is no more events to process
): VoidFunction {
  const canvasMatrix = getCanvasMatrix(canvas)
  let canvasPass: GPURenderPassEncoder

  const pickManager = new PickManager(device)
  let pickMatrix: Float32Array
  let pickPass: GPURenderPassEncoder

  const loadingTexture = getLoadingTexture(device)

  connect_web_gpu_programs({
    draw_texture: (vertex_data, texture_id) =>
      drawTexture(
        canvasPass,
        canvasMatrix,
        vertex_data.typedArray,
        textures[texture_id].texture ?? loadingTexture
      ),
    draw_msdf: (vertex_data, texture_id) => {
      drawMSDF(
        canvasPass,
        canvasMatrix,
        vertex_data.typedArray,
        textures[texture_id].texture ?? loadingTexture
      )
    },
    draw_triangle: (vertex_data) => drawTriangle(canvasPass, canvasMatrix, vertex_data.typedArray),
    pick_texture: (vertex_data, texture_id) =>
      pickTexture(
        pickPass,
        pickMatrix,
        vertex_data.typedArray,
        textures[texture_id].texture ?? loadingTexture
      ),
    pick_triangle: (vertex_data) => pickTriangle(pickPass, pickMatrix, vertex_data.typedArray),
  })

  let rafId = 0
  const lastPickPointer: Point = { x: 0, y: 0 }

  function draw(now: DOMHighResTimeStamp) {
    const encoder = device.createCommandEncoder()

    const canvasDescriptor = getCanvasRenderDescriptor(context, device)
    canvasPass = encoder.beginRenderPass(canvasDescriptor)
    canvas_render()
    canvasPass.end()

    if (pointer.afterPickEventsQueue.length === 0) {
      onEmptyEvents()
    }

    const needsUpdatePick =
      pointer.afterPickEventsQueue.length > 0 ||
      lastPickPointer.x !== pointer.x ||
      lastPickPointer.y !== pointer.y

    if (needsUpdatePick) {
      lastPickPointer.x = pointer.x
      lastPickPointer.y = pointer.y
      pickMatrix = pickManager.createMatrix(canvas, canvasMatrix)
      const pick = pickManager.startPicking(encoder)
      pickPass = pick.pass
      picks_render()
      pick.end()
    }

    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])

    pickManager.asyncPick()

    rafId = requestAnimationFrame(draw)
  }

  rafId = requestAnimationFrame(draw)

  return () => {
    cancelAnimationFrame(rafId)
  }
}
