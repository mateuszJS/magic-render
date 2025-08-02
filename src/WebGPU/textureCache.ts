import { canvasMatrixBuffer } from 'WebGPU/programs/initPrograms'
import mat4 from 'utils/mat4'
import { updateRenderPass } from 'run'
import * as Textures from 'textures'
import getMultisampleTexture from 'getMultisampleTexture'

let endCacheCallback: VoidFunction = () => {
  throw new Error('Cache not started')
}

export function endCache() {
  endCacheCallback()
}

export function startCache(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  currTextureId: number | null,
  boundingBox: BoundingBox,
  outputWWidth: number,
  outputHeight: number
): number {
  const width = boundingBox.max_x - boundingBox.min_x
  const height = boundingBox.max_y - boundingBox.min_y

  const texture = device.createTexture({
    label: 'texture cache',
    format: presentationFormat,
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    size: [outputWWidth, outputHeight],
  })

  const encoder = device.createCommandEncoder()

  const multisampleTexture = getMultisampleTexture(
    device,
    outputWWidth,
    outputHeight,
    presentationFormat
  )
  const descriptor: GPURenderPassDescriptor = {
    label: 'texture cache pass',
    colorAttachments: [
      {
        view: multisampleTexture.createView(),
        resolveTarget: texture.createView(),
        loadOp: 'clear',
        storeOp: 'store',
      },
    ],
  }

  const pass = encoder.beginRenderPass(descriptor)
  updateRenderPass(pass)
  const matrix = mat4.ortho(
    boundingBox.min_x, // left
    boundingBox.min_x + width, // right
    boundingBox.min_y + height, // bottom
    boundingBox.min_y, // top, yes top and bottom and reversed on purpose to make texture start at bottom-left corner
    1, // near
    -1 // far
  )

  device.queue.writeBuffer(canvasMatrixBuffer, 0, matrix)

  endCacheCallback = () => {
    pass.end()
    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])
  }

  return Textures.setTexture(texture, currTextureId)
}
