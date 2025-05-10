import mat4 from "utils/mat4"
import { pointer } from "./pointer"

const NUM_PIXELS = 1

export default class PickManager {

  private pickBuffer: GPUBuffer
  private pickTexture: GPUTexture
  private pickDepthTexture: GPUTexture
  private isPreviousDone = true

  public lastPick = 0

  constructor (
    private device: GPUDevice,
    private canvas: HTMLElement,
  ) {
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

  render(
    encoder: GPUCommandEncoder,
    drawingMatrix: Float32Array,
    renderPicks: (pass: GPURenderPassEncoder, matrix: Float32Array) => void,
    debugRenderPass?: GPURenderPassEncoder,
  ) {
    const { clientWidth, clientHeight } = this.canvas

    if (debugRenderPass) {
      const tx = -(2 * (pointer.x / clientWidth) - 1)
      const ty = 2 * (pointer.y / clientHeight) - 1

      const pickMatrix = [
        mat4.scaling([clientWidth, clientHeight, 0]), // scale to 1px convers whole shader output
        mat4.translation([tx, ty, 0]),
        drawingMatrix,
      ].reduce(
        (accMatrix, rotationMatrix) => mat4.multiply(accMatrix, rotationMatrix),
        mat4.translation([-1, 1, 0]) // move (0,0) to the top left corner
      )
      
      // setExtraMatrix(extraMatrix)
      // const {worldMatrix} = getMatricies(this.canvas, 0)
      // setExtraMatrix(null)
  
      // const pass = encoder.beginRenderPass(descriptor)
      // const width = 1
      // const height = 1
      // pass.setViewport(0, 0, width, height, 0, 1)
      // Set the scissor rectangle to clip rendering to the 1x1 area
      // pass.setScissorRect(0, 0, width, height)
  
      renderPicks(debugRenderPass, pickMatrix)
      return
      // pass.end()
    }

    const descriptor: GPURenderPassDescriptor = {
      // describe which textures we want to raw to and how use them
      label: "our render to canvas renderPass",
      colorAttachments: [
        {
          view: this.pickTexture.createView(),
          loadOp: "clear",
          clearValue: [0, 0, 0, 1],
          storeOp: "store",
        } as const,
      ],
      depthStencilAttachment: {
        view: this.pickDepthTexture.createView(), // placholder to calm down TS
        depthLoadOp: 'clear',
        depthClearValue: 1.0,
        depthStoreOp: 'discard',
      } as const,
    }
    const tx = -(2 * (pointer.x / clientWidth) - 1)
    const ty = 2 * (pointer.y / clientHeight) - 1

    const pickMatrix = [
      mat4.translation([tx * clientWidth, ty * clientHeight, 0]),
      mat4.scaling([clientWidth, clientHeight, 1]),
    ].reduce(
      (accMatrix, rotationMatrix) => mat4.multiply(accMatrix, rotationMatrix),
      drawingMatrix
    )
    
    // setExtraMatrix(extraMatrix)
    // const {worldMatrix} = getMatricies(this.canvas, 0)
    // setExtraMatrix(null)

    const pass = encoder.beginRenderPass(descriptor)
    const width = 1
    const height = 1
    pass.setViewport(0, 0, width, height, 0, 1)
    // Set the scissor rectangle to clip rendering to the 1x1 area
    pass.setScissorRect(0, 0, width, height)

    renderPicks(pass, pickMatrix)

    pass.end()


    encoder.copyTextureToBuffer({
      texture: this.pickTexture,
      origin: { x: 0, y: 0 }
    }, {
      buffer: this.pickBuffer,
      bytesPerRow: ((NUM_PIXELS * 4 + 255) | 0) * 256,
      rowsPerImage: 1,
    }, {
      width: NUM_PIXELS,
    })
  }

  async asyncPick() {
    if (!this.isPreviousDone) return
    this.isPreviousDone = false
    await this.pickBuffer.mapAsync(GPUMapMode.READ, 0, 4 * NUM_PIXELS)
    const ids = new Uint32Array(this.pickBuffer.getMappedRange(0, 4 * NUM_PIXELS))

    this.lastPick = ids[0]
    console.log('pick id', this.lastPick)
    this.pickBuffer.unmap()
    this.isPreviousDone = true
  }
}