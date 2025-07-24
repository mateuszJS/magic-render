import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  drawMSDF,
  pickTexture,
  pickTriangle,
  canvasMatrixBuffer,
  pickCanvasMatrixBuffer,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import { canvas_render, picks_render, connect_web_gpu_programs } from 'logic/index.zig'
import { pointer } from 'WebGPU/pointer'
import * as Textures from 'textures'

export const transformMatrix = new Float32Array()
export const MAP_BACKGROUND_SCALE = 1000

export default function runCreator(
  canvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  onEmptyEvents: VoidFunction // call when there is no more events to process
): VoidFunction {
  let canvasPass: GPURenderPassEncoder
  let pickPass: GPURenderPassEncoder

  const pickManager = new PickManager(device)
  // let time = 0
  // let total = 0
  // let samplesCount = 0

  connect_web_gpu_programs({
    draw_texture: (vertex_data, texture_id) =>
      drawTexture(canvasPass, vertex_data.typedArray, Textures.getTexture(texture_id)),
    draw_msdf: (vertex_data, texture_id) => {
      drawMSDF(canvasPass, vertex_data.typedArray, Textures.getTexture(texture_id))
    },
    draw_triangle: (vertex_data) => {
      const zigPtr = (vertex_data as Record<string, unknown>)['*']
      const dataView = (zigPtr as { dataView: DataView }).dataView
      // started with 0.18 and goes to 0.16
      drawTriangle(canvasPass, dataView.buffer, dataView.byteOffset, dataView.byteLength)
      /*
      samplesCount++
      total += performance.now() - time
      if (samplesCount % 100 === 0) {
        console.log('Average draw time:', total / samplesCount)
      }
      */
    },
    pick_texture: (vertex_data, texture_id) =>
      pickTexture(pickPass, vertex_data.typedArray, Textures.getTexture(texture_id)),
    pick_triangle: (vertex_data) => pickTriangle(pickPass, vertex_data.typedArray),
  })

  let rafId = 0
  const lastPickPointer: Point = { x: 0, y: 0 }

  function draw(_now: DOMHighResTimeStamp) {
    const encoder = device.createCommandEncoder()

    const canvasDescriptor = getCanvasRenderDescriptor(context, device)
    canvasPass = encoder.beginRenderPass(canvasDescriptor)
    const canvasMatrix = getCanvasMatrix(canvas)
    device.queue.writeBuffer(canvasMatrixBuffer, 0, canvasMatrix)
    // time = performance.now()
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
      const pickMatrix = pickManager.createMatrix(canvas, canvasMatrix)
      device.queue.writeBuffer(pickCanvasMatrixBuffer, 0, pickMatrix)
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
