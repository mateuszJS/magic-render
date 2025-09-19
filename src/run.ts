import getCanvasRenderDescriptor from 'getCanvasRenderDescriptor'
import {
  drawTexture,
  drawTriangle,
  pickTexture,
  pickTriangle,
  pickCanvasMatrixBuffer,
  drawSolidShape,
  drawLinearGradientShape,
  drawRadialGradientShape,
  computeShape,
  pickShape,
  drawBlur,
  canvasMatrix,
  destroyGpuObjects,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import * as Logic from 'logic/index.zig'
import { pointer } from 'pointer'
import * as Textures from 'textures'
import { endCache, startCache } from 'WebGPU/textureCache'

let renderPass: GPURenderPassEncoder
export function updateRenderPass(newRenderPass: GPURenderPassEncoder) {
  renderPass = newRenderPass
}

export default function runCreator(
  creatorCanvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  onEmptyEvents: VoidFunction // call when there is no more events to process
) {
  let pickPass: GPURenderPassEncoder
  let computePass: GPUComputePassEncoder
  let encoder: GPUCommandEncoder

  const pickManager = new PickManager(device)

  Logic.connectCacheCallbacks(
    Textures.createCacheTexture,
    (texture_id: number, box: BoundingBox, width: number, height: number) => {
      startCache(device, encoder, texture_id, box, width, height)
    },
    endCache
  )

  // let time = 0
  // let total = 0
  // let samplesCount = 0
  Logic.connectWebGpuPrograms({
    draw_texture: (vertex_data, texture_id) => {
      drawTexture(renderPass, vertex_data.dataView, Textures.getTextureSafe(texture_id))
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
      // console.log(curves_data, width, height, textureId)
      computeShape(computePass, curvesDataView, Textures.getTexture(textureId))
    },
    draw_blur: (
      textureId,
      iterations,
      filterSizePerPassX,
      filterSizePerPassY,
      sigmaPerPassX,
      sigmaPerPassY
    ) => {
      drawBlur(
        encoder,
        Textures.getTexture(textureId),
        iterations,
        filterSizePerPassX,
        filterSizePerPassY,
        sigmaPerPassX,
        sigmaPerPassY
      )
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
    pick_shape: (bound_box_data, uniform, textureId) => {
      pickShape(
        pickPass,
        bound_box_data['*'].dataView,
        uniform.dataView,
        Textures.getTexture(textureId)
      )
    },
    pick_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      pickTriangle(pickPass, dataView)
    },
  })

  let rafId = 0
  const lastPickPointer: Point = { x: 0, y: 0 }

  /*===========PRERENDER ICONS SDF===============*/
  encoder = device.createCommandEncoder({
    label: 'prerender ui elements SDF',
  })
  computePass = encoder.beginComputePass()
  Logic.generateUiElementsSdf()
  computePass.end()
  device.queue.submit([encoder.finish()])

  /*===========MAIN LOOP FUNCTION===============*/
  function draw(
    now: DOMHighResTimeStamp,
    preview?: { canvas: HTMLCanvasElement; ctx: GPUCanvasContext; onCapture: VoidFunction }
  ) {
    Logic.tick(now)

    encoder = device.createCommandEncoder({
      label: 'draw canvas main encoder',
    })

    computePass = encoder.beginComputePass()
    Logic.calculateShapesSDF()
    computePass.end()

    Logic.updateCache()

    const canvasDescriptor = getCanvasRenderDescriptor(preview?.ctx || context, device)
    renderPass = encoder.beginRenderPass(canvasDescriptor)

    const matrix = getCanvasMatrix(preview?.canvas || creatorCanvas)
    device.queue.writeBuffer(canvasMatrix.buffer, 0, matrix)
    // time = performance.now()
    Logic.renderDraw()
    renderPass.end()

    if (preview) {
      const commandBuffer = encoder.finish()
      device.queue.submit([commandBuffer])
      destroyGpuObjects()
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
      const pickMatrix = pickManager.createMatrix(creatorCanvas, matrix)
      device.queue.writeBuffer(pickCanvasMatrixBuffer, 0, pickMatrix)
      const pick = pickManager.startPicking(encoder)
      pickPass = pick.pass
      Logic.renderPick()
      pick.end()
    }

    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])
    destroyGpuObjects()

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
