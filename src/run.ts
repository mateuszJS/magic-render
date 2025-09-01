import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  drawMSDF,
  pickTexture,
  pickTriangle,
  canvasMatrixBuffer,
  pickCanvasMatrixBuffer,
  drawSolidShape,
  drawLinearGradientShape,
  drawRadialGradientShape,
  computeShape,
  pickShape,
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
  Logic.connectWebGpuPrograms({
    draw_texture: (vertex_data, texture_id) => {
      drawTexture(renderPass, vertex_data.dataView, Textures.getTextureSafe(texture_id))
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
    compute_shape: (curves_data, width, height, textureId) => {
      const curvesDataView = curves_data['*'].dataView
      Textures.updateSDF(textureId, width, height)
      computeShape(computePass, curvesDataView, Textures.getTexture(textureId))
    },
    draw_shape: (bound_box_data, uniform_data, textureId) => {
      let program
      let uniform
      if ('linear' in uniform_data && uniform_data.linear) {
        program = drawLinearGradientShape
        uniform = uniform_data.linear
      } else if ('radial' in uniform_data && uniform_data.radial) {
        program = drawRadialGradientShape
        uniform = uniform_data.radial
      } else if ('solid' in uniform_data && uniform_data.solid) {
        program = drawSolidShape
        uniform = uniform_data.solid
      } else {
        throw Error('Unsupported shape uniform type')
      }

      const boundBoxDataView = bound_box_data['*'].dataView
      program(renderPass, Textures.getTexture(textureId), boundBoxDataView, uniform.dataView)
    },
    pick_texture: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      pickTexture(pickPass, dataView, Textures.getTextureSafe(texture_id))
    },
    pick_shape: (bound_box_data, strokeWidth, textureId) => {
      pickShape(pickPass, bound_box_data['*'].dataView, strokeWidth, Textures.getTexture(textureId))
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
