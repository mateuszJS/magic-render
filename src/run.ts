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
  combineSdf,
  clearSdf,
  clearComputeDepth,
  renderShapeSdf,
} from 'WebGPU/programs/initPrograms'
import getCanvasMatrix from 'getCanvasMatrix'
import PickManager from 'WebGPU/pick'
import * as Logic from 'logic/index.zig'
import { camera, pointer } from 'pointer'
import * as Textures from 'textures'
import { endCache, startCache } from 'WebGPU/textureCache'
import { BoundingBox, Point } from 'types'
import * as CustomPrograms from 'customPrograms'
import assertUnreachable from 'utils/assertUnreachable'
// import { TimingHelper, NonNegativeRollingAverage } from 'WebGPU/TimingHelper'

let renderPass: GPURenderPassEncoder
export function updateRenderPass(newRenderPass: GPURenderPassEncoder) {
  renderPass = newRenderPass
}

export function runCreator(
  creatorCanvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  onEmptyEvents: VoidFunction, // call when there is no more events to process
  captureError: (err: unknown) => void
) {
  let pickPass: GPURenderPassEncoder
  let encoder: GPUCommandEncoder
  let combineSdfRenderPass: GPURenderPassEncoder

  const pickManager = new PickManager(device)

  // https://webgpufundamentals.org/webgpu/lessons/webgpu-timing.html
  // const timingHelper = new TimingHelper(device)
  // const gpuAverage = new NonNegativeRollingAverage()

  Logic.glueJsTextureCache(
    Textures.createCacheTexture,
    (texture_id: number, box: BoundingBox, width: number, height: number) => {
      startCache(device, encoder, texture_id, box, width, height)
    },
    endCache
  )

  Logic.connectWebGpuPrograms({
    draw_texture: (vertex_data, texture_id) => {
      drawTexture(renderPass, vertex_data.dataView, Textures.getTextureSafe(texture_id))
    },
    draw_triangle: (vertex_data) => {
      const dataView = vertex_data['*'].dataView
      drawTriangle(renderPass, dataView)
    },
    compute_shape: (curves_data, width, height, textureId) => {
      const curvesDataView = curves_data['*'].dataView
      Textures.update(textureId, width, height)
      renderShapeSdf(encoder, curvesDataView, Textures.getTexture(textureId))
      // computeShape(computePass, curvesDataView, Textures.getTexture(textureId))
    },
    start_combine_sdf: (sdfTextureId, computeDepthTextureId, width, height) => {
      Textures.update(sdfTextureId, width, height)
      Textures.update(computeDepthTextureId, width, height)

      combineSdfRenderPass = encoder.beginRenderPass({
        label: 'combone SDFs',
        colorAttachments: [
          {
            view: Textures.getTexture(sdfTextureId).createView(),
            loadOp: 'clear',
            clearValue: {
              r: -3.402823466e38,
              g: 0,
              b: 0,
              a: 0,
            },
            storeOp: 'store',
          },
        ],
        depthStencilAttachment: {
          view: Textures.getTexture(computeDepthTextureId).createView(),
          depthClearValue: 0, //-3.402823466e38,
          depthLoadOp: 'clear',
          depthStoreOp: 'store',
        },
      })
    },
    combine_sdf: (
      destinationTexId,
      sourceTexId,
      computeDepthTextureId,
      uniformData,
      curves_data
    ) => {
      const curvesDataView = curves_data['*'].dataView
      combineSdf(
        combineSdfRenderPass,
        Textures.getTexture(destinationTexId),
        Textures.getTexture(sourceTexId),
        uniformData.dataView,
        curvesDataView
      )
    },
    finish_combine_sdf: () => {
      combineSdfRenderPass.end()
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
    draw_shape: (bound_box_data, uniform_data, textureId, curves_data, uniform_t) => {
      const curvesDataView = curves_data['*'].dataView
      const uniformDataView = uniform_t['*'].dataView

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
      } else if ('program' in uniform_data && uniform_data.program) {
        const programId = uniform_data.program.dataView.getUint32(0, true)
        program = CustomPrograms.getExecutable(programId)
        uniform = uniform_data.program
      } else {
        assertUnreachable(uniform_data)
      }

      const boundBoxDataView = bound_box_data['*'].dataView
      program(
        renderPass,
        Textures.getTexture(textureId),
        boundBoxDataView,
        uniform.dataView,
        curvesDataView,
        uniformDataView
      )
    },
    pick_texture: (vertex_data, texture_id) => {
      const dataView = vertex_data['*'].dataView
      pickTexture(pickPass, dataView, Textures.getTextureSafe(texture_id))
    },
    pick_shape: (bound_box_data, uniform, textureId, curves_data, uniform_t) => {
      const curvesDataView = curves_data['*'].dataView
      const uniformDataView = uniform_t['*'].dataView

      pickShape(
        pickPass,
        bound_box_data['*'].dataView,
        uniform.dataView,
        Textures.getTexture(textureId),
        curvesDataView,
        uniformDataView
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
  try {
    Logic.generateUiElementsSdf()
  } catch (err) {
    captureError(err)
  }
  device.queue.submit([encoder.finish()])

  /*===========MAIN LOOP FUNCTION===============*/
  function draw(now: DOMHighResTimeStamp, previewCtx?: GPUCanvasContext) {
    try {
      const isDrawNeeded = Logic.tick(now) || camera.redrawNeeded

      encoder = device.createCommandEncoder({
        label: 'main encoder',
      })

      Logic.computePhase()
      Logic.updateCache()

      const matrix = getCanvasMatrix(previewCtx?.canvas || creatorCanvas)
      device.queue.writeBuffer(canvasMatrix.buffer, 0, matrix)

      // time = performance.now()
      if (isDrawNeeded) {
        const canvasDescriptor = getCanvasRenderDescriptor(previewCtx || context, device)
        renderPass = encoder.beginRenderPass(canvasDescriptor)
        Logic.renderDraw(!!previewCtx)
        renderPass.end()
        camera.redrawNeeded = false
      }

      if (previewCtx) {
        const commandBuffer = encoder.finish()
        device.queue.submit([commandBuffer])
        destroyGpuObjects()
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

      // const computePass = timingHelper.beginComputePass(encoder, { label: 'blur-pass' })
      // timingHelper.getResult().then((gpuTime) => {
      //   if (typeof gpuTime === 'number') {
      //     gpuAverage.addSample(gpuTime / 1000)
      //   }
      // })

      destroyGpuObjects()

      pickManager.asyncPick()

      rafId = requestAnimationFrame(draw)
    } catch (err) {
      captureError(err)
    }
  }

  rafId = requestAnimationFrame(draw)

  function stopRAF() {
    cancelAnimationFrame(rafId)
  }

  const capturePreview = (previewCtx: GPUCanvasContext, collectAndCleanup: VoidFunction) => {
    stopRAF()
    draw(performance.now(), previewCtx)
    collectAndCleanup()
    rafId = requestAnimationFrame(draw)
  }

  return {
    stopRAF,
    capturePreview,
  }
}
