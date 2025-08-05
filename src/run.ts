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

let renderPass: GPURenderPassEncoder
export function updateRenderPass(newRenderPass: GPURenderPassEncoder) {
  renderPass = newRenderPass
}

export default function runCreator(
  creatorCanvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  cleanupPrograms: VoidFunction,
  presentationFormat: GPUTextureFormat,
  onEmptyEvents: VoidFunction // call when there is no more events to process
) {
  let pickPass: GPURenderPassEncoder

  const pickManager = new PickManager(device)
  // let time = 0
  // let total = 0
  // let samplesCount = 0

  connect_web_gpu_programs({
    draw_texture: (vertex_data, texture_id) => {
      drawTexture(renderPass, vertex_data.dataView, Textures.getTexture(texture_id))
    },
    draw_msdf: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      drawMSDF(renderPass, dataView, Textures.getTexture(texture_id))
    },
    draw_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      drawTriangle(renderPass, dataView)
      /*
      samplesCount++
      total += performance.now() - time
      if (samplesCount % 100 === 0) {
        console.log('Average draw time:', total / samplesCount)
      }
      */
    },
    draw_shape: (curves_data, bound_box_data, uniform_data) => {
      const curvesDataView = curves_data['*'].dataView
      const boundBoxDataView = bound_box_data['*'].dataView
      drawShape(renderPass, curvesDataView, boundBoxDataView, uniform_data.dataView)

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
      pickTexture(pickPass, dataView, Textures.getTexture(texture_id))
    },
    pick_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      pickTriangle(pickPass, dataView)
    },
  })

  let rafId = 0
  const lastPickPointer: Point = { x: 0, y: 0 }

  // when previewCanvas is present then onCapturePreview should be as well
  function draw(
    now: DOMHighResTimeStamp,
    preview?: { canvas: HTMLCanvasElement; ctx: GPUCanvasContext; onCapture: VoidFunction }
  ) {
    const encoder = device.createCommandEncoder()
    const canvasDescriptor = getCanvasRenderDescriptor(preview?.ctx || context, device)
    renderPass = encoder.beginRenderPass(canvasDescriptor)
    const canvasMatrix = getCanvasMatrix(preview?.canvas || creatorCanvas)
    device.queue.writeBuffer(canvasMatrixBuffer, 0, canvasMatrix)
    // time = performance.now()
    render_draw()
    renderPass.end()

    if (preview) {
      const commandBuffer = encoder.finish()
      device.queue.submit([commandBuffer])
      cleanupPrograms()
      preview.onCapture()
      return
    }

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
      const pickMatrix = pickManager.createMatrix(creatorCanvas, canvasMatrix)
      device.queue.writeBuffer(pickCanvasMatrixBuffer, 0, pickMatrix)
      const pick = pickManager.startPicking(encoder)
      pickPass = pick.pass
      render_pick()
      pick.end()
    }

    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])
    cleanupPrograms()

    pickManager.asyncPick()

    rafId = requestAnimationFrame(draw)
  }

  rafId = requestAnimationFrame(draw)

  function stopRAF() {
    cancelAnimationFrame(rafId)
  }

  function capturePreview(canvas: HTMLCanvasElement, ctx: GPUCanvasContext): Promise<void> {
    stopRAF()
    const promise = new Promise<void>((resolve) => {
      draw(performance.now(), { canvas, ctx, onCapture: resolve })
    })
    rafId = requestAnimationFrame(draw)
    return promise
  }

  return {
    stopRAF,
    capturePreview,
  }
}
