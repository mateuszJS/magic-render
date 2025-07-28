import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  drawMSDF,
  pickTexture,
  pickTriangle,
  canvasMatrixBuffer,
  pickCanvasMatrixBuffer,
  drawShape,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import { render_draw, render_pick, connect_web_gpu_programs } from 'logic/index.zig'
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
    draw_texture: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      // console.log(
      //   new Float32Array(
      //     dataView.buffer.slice(dataView.byteOffset, dataView.byteOffset + dataView.byteLength)
      //   )
      // )
      drawTexture(
        canvasPass,
        dataView.buffer,
        dataView.byteOffset,
        dataView.byteLength,
        Textures.getTexture(texture_id)
      )
    },
    draw_msdf: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      drawMSDF(
        canvasPass,
        dataView.buffer,
        dataView.byteOffset,
        dataView.byteLength,
        Textures.getTexture(texture_id)
      )
    },
    draw_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      drawTriangle(canvasPass, dataView.buffer, dataView.byteOffset, dataView.byteLength)
      /*
      samplesCount++
      total += performance.now() - time
      if (samplesCount % 100 === 0) {
        console.log('Average draw time:', total / samplesCount)
      }
      */
    },
    pick_texture: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      // const uints = new Uint32Array(
      //   dataView.buffer.slice(dataView.byteOffset, dataView.byteOffset + dataView.byteLength)
      // )
      // for (let i = 0; i < uints.length; i += 5) {
      //   console.log('texture id', uints[i + 4])
      // }
      pickTexture(
        pickPass,
        dataView.buffer,
        dataView.byteOffset,
        dataView.byteLength,
        Textures.getTexture(texture_id)
      )
    },
    pick_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      pickTriangle(pickPass, dataView.buffer, dataView.byteOffset, dataView.byteLength)
    },
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
    render_draw()

    // Define cubic Bézier curves that form the shape boundary
    const curves: Point[] = [
      { x: 100, y: 100 - 100 },
      { x: 300, y: 500 - 100 },
      { x: 600, y: 700 - 100 },
      { x: 500, y: 200 - 100 },
      { x: 300, y: -200 },
      { x: 400, y: -300 },
      { x: 100, y: 100 - 100 },
    ]

    drawShape(canvasPass, curves)

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
      render_pick()
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
