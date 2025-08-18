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
  computeSDF,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import * as Logic from 'logic/index.zig'
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
  let computePass: GPUComputePassEncoder

  const pickManager = new PickManager(device)
  // let time = 0
  // let total = 0
  // let samplesCount = 0

  const textureSDF = device.createTexture({
    label: 'SDF texture',
    size: [500, 500],
    format: 'rgba32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })

  Logic.connectWebGpuPrograms({
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
    compute_shape: (curves_data) => {
      const curvesDataView = curves_data['*'].dataView

      // const boundBoxDataView = bound_box_data['*'].dataView
      computeSDF(computePass, curvesDataView, textureSDF)
      // drawShape(renderPass, curvesDataView, boundBoxDataView, uniform_data.dataView)

      /*
      samplesCount++
      total += performance.now() - time
      if (samplesCount % 100 === 0) {
        console.log('Average draw time:', total / samplesCount)
      }
      */
    },
    draw_shape: (bound_box_data, uniform_data) => {
      const boundBoxDataView = bound_box_data['*'].dataView

      drawShape(renderPass, textureSDF, boundBoxDataView, uniform_data.dataView)
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

  function draw(
    now: DOMHighResTimeStamp,
    preview?: { canvas: HTMLCanvasElement; ctx: GPUCanvasContext; onCapture: VoidFunction }
  ) {
    const encoder = device.createCommandEncoder()

    computePass = encoder.beginComputePass()
    Logic.calculateShapesSDF()
    computePass.end()

    const canvasDescriptor = getCanvasRenderDescriptor(preview?.ctx || context, device)
    renderPass = encoder.beginRenderPass(canvasDescriptor)
    const canvasMatrix = getCanvasMatrix(preview?.canvas || creatorCanvas)
    device.queue.writeBuffer(canvasMatrixBuffer, 0, canvasMatrix)
    // time = performance.now()
    Logic.renderDraw()
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
      Logic.renderPick()
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

  const capturePreview = (canvas: HTMLCanvasElement, ctx: GPUCanvasContext) =>
    new Promise<void>((resolve) => {
      stopRAF()
      draw(performance.now(), { canvas, ctx, onCapture: resolve })
      rafId = requestAnimationFrame(draw)
    })

  return {
    stopRAF,
    capturePreview,
  }
}
