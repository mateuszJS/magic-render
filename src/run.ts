import getCanvasRenderDescriptor from "getCanvasRenderDescriptor"
import { drawTexture, drawTriangle, pickTexture } from "WebGPU/programs/initPrograms"
// import { State } from "../crate/glue_code"
import getCanvasMatrix from "getCanvasMatrix"
import PickManager from "WebGPU/pick"
import { canvas_render, picks_render, connectWebGPUPrograms } from "logic/index.zig"

export const transformMatrix = new Float32Array()
export const MAP_BACKGROUND_SCALE = 1000

export default function runCreator(
  // state: State,
  canvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  textures: GPUTexture[],
) {
  const canvasMatrix = getCanvasMatrix(canvas)
  let canvasPass: GPURenderPassEncoder
  
  const pickManager = new PickManager(device)
  let pickMatrix: Float32Array
  let pickPass: GPURenderPassEncoder
  

  connectWebGPUPrograms({
    draw_texture: (vertex_data, texture_id) => drawTexture(
      canvasPass,
      canvasMatrix,
      new Float32Array([...vertex_data]),
      textures[texture_id]
    ),
    draw_triangle: (vertex_data) => drawTriangle(
      canvasPass,
      canvasMatrix,
      new Float32Array([...vertex_data])
    ),
    pick_texture: (vertex_data, texture_id) => pickTexture(
      pickPass,
      pickMatrix,
      new Float32Array([...vertex_data]),
      textures[texture_id]
    ),
  })

  function draw(now: DOMHighResTimeStamp) {
    // const { needsRefresh } = state; // make save copy of needsRefresh value
    // state.needsRefresh = false; // set next needsRefresh to false by default

    // if (needsRefresh) {
      const encoder = device.createCommandEncoder()

      const canvasDescriptor = getCanvasRenderDescriptor(context, device)
      canvasPass = encoder.beginRenderPass(canvasDescriptor)
      canvas_render()
      canvasPass.end()

      pickMatrix = pickManager.createMatrix(canvas, canvasMatrix)
      const pick = pickManager.startPicking(encoder)
      pickPass = pick.pass
      picks_render()
      pick.end()

      const commandBuffer = encoder.finish()
      device.queue.submit([commandBuffer])

      pickManager.asyncPick()

    requestAnimationFrame(draw)
  }

  requestAnimationFrame(draw)
}
