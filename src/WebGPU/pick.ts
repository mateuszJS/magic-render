import mat4 from 'utils/mat4'
import { pointer } from './pointer'
import { on_update_pick } from '../logic/index.zig'

const NUM_PIXELS = 1

export default class PickManager {
  private pickBuffer: GPUBuffer
  private pickTexture: GPUTexture
  private pickDepthTexture: GPUTexture
  private isPreviousPickDone = true

  constructor(device: GPUDevice) {
    this.pickBuffer = device.createBuffer({
      size: NUM_PIXELS * 4,
      usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST,
    })

    this.pickTexture = device.createTexture({
      size: [1, 1],
      format: 'r32uint',
      usage: GPUTextureUsage.COPY_SRC | GPUTextureUsage.RENDER_ATTACHMENT,
    })

    this.pickDepthTexture = device.createTexture({
      size: [1, 1],
      format: 'depth24plus',
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    })
  }

  /**
   * Starts a picking render pass.
   * @param encoder The GPUCommandEncoder to use for the render pass.
   * @returns An object which contains render pass and a callback to end picking.
   */
  startPicking(encoder: GPUCommandEncoder): { pass: GPURenderPassEncoder; end: VoidFunction } {
    const descriptor: GPURenderPassDescriptor = {
      // describe which textures we want to raw to and how use them
      label: 'our render to canvas renderPass',
      colorAttachments: [
        {
          view: this.pickTexture.createView(),
          loadOp: 'clear',
          clearValue: [0, 0, 0, 1],
          storeOp: 'store',
        } as const,
      ],
      // depthStencilAttachment: {
      //   view: this.pickDepthTexture.createView(), // placholder to calm down TS
      //   depthLoadOp: 'clear',
      //   depthClearValue: 1.0,
      //   depthStoreOp: 'discard',
      // } as const,
    }

    const pass = encoder.beginRenderPass(descriptor)

    const width = 1
    const height = 1
    pass.setViewport(0, 0, width, height, 0, 1)
    // Set the scissor rectangle to clip rendering to the 1x1 area
    pass.setScissorRect(0, 0, width, height)

    const endPicking = () => {
      pass.end()

      if (this.isPreviousPickDone) {
        encoder.copyTextureToBuffer(
          {
            texture: this.pickTexture,
            origin: { x: 0, y: 0 },
          },
          {
            buffer: this.pickBuffer,
          },
          {
            width: NUM_PIXELS,
          }
        )
      }
    }

    return { pass, end: endPicking }
  }

  createMatrix(canvas: HTMLCanvasElement, canvasMatrix: Float32Array) {
    const { clientWidth, clientHeight } = canvas

    const tx = -(2 * (pointer.x / clientWidth) - 1)
    const ty = 2 * (pointer.y / clientHeight) - 1

    const pickMatrix = [
      mat4.scaling([clientWidth, clientHeight, 0]), // scale to 1px convers whole shader output
      mat4.translation([tx, ty, 0]),
      canvasMatrix,
    ].reduce(
      (accMatrix, rotationMatrix) => mat4.multiply(accMatrix, rotationMatrix),
      mat4.translation([-1, 1, 0]) // move (0,0) to the top left corner
    )

    return pickMatrix
  }

  async asyncPick() {
    if (!this.isPreviousPickDone) return
    this.isPreviousPickDone = false
    try {
      await this.pickBuffer.mapAsync(GPUMapMode.READ, 0, 4 * NUM_PIXELS)
      const [id] = new Uint32Array(this.pickBuffer.getMappedRange(0, 4 * NUM_PIXELS))
      on_update_pick(id)

      let i = 0
      while (i < pointer.afterPickEventsQueue.length) {
        const { requireNewPick, cb } = pointer.afterPickEventsQueue[i]
        if (requireNewPick && i > 0) break // we need to start new picking pass
        cb()
        i++
      }
      pointer.afterPickEventsQueue.splice(0, i) // remove processed events

      this.pickBuffer.unmap()
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
    } catch (err) {
      /* ignorign errors when map fails because device was destroyed(so buffer too and was unmapped before mapAsync completed)*/
    }
    this.isPreviousPickDone = true
  }
}
