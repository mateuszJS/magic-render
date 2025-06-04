import getCanvasRenderDescriptor from "getCanvasRenderDescriptor"
import { drawTexture, drawTriangle, pickTexture } from "WebGPU/programs/initPrograms"
// import { State } from "../crate/glue_code"
import getCanvasMatrix from "getCanvasMatrix"
import PickManager from "WebGPU/pick"
import { get_shader_input, get_shader_pick_input, get_border } from "logic/index.zig"

export const transformMatrix = new Float32Array()
export const MAP_BACKGROUND_SCALE = 1000

export default function runCreator(
  // state: State,
  canvas: HTMLCanvasElement,
  context: GPUCanvasContext,
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  textures: GPUTexture[],
  assetsList: number[]
) {
  const matrix = getCanvasMatrix(canvas)
  const pickManager = new PickManager(device, canvas)

  function draw(now: DOMHighResTimeStamp) {
    // const { needsRefresh } = state; // make save copy of needsRefresh value
    // state.needsRefresh = false; // set next needsRefresh to false by default

    // if (needsRefresh) {
      const encoder = device.createCommandEncoder()
      const descriptor = getCanvasRenderDescriptor(context, device)
      const pass = encoder.beginRenderPass(descriptor)

      assetsList.forEach((id) => {
        const { texture_id, vertex_data } = get_shader_input(id)
        drawTexture(pass, matrix, new Float32Array(vertex_data), textures[texture_id])
      })

      const borderVertexData = get_border()
      if (borderVertexData.length > 0) {
        // console.log('borderVertexData', borderVertexData.length)
        drawTriangle(pass, matrix, new Float32Array([...borderVertexData]))
      }

      pass.end()

      pickManager.render(encoder, matrix, (pickPass, pickMatrix) => {
        assetsList.forEach((id) => {
          const { texture_id, vertex_data } = get_shader_pick_input(id)
          pickTexture(pickPass, pickMatrix, new Float32Array([...vertex_data]), textures[texture_id])
        })
      }, pass)

      const commandBuffer = encoder.finish()
      device.queue.submit([commandBuffer])

      pickManager.asyncPick()

    requestAnimationFrame(draw)
  }

  requestAnimationFrame(draw)
}
