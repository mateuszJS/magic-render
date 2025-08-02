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
  textureId: number | null,
  boundingBox: BoundingBox
): number {
  const width = boundingBox.max_x - boundingBox.min_x
  const height = boundingBox.max_y - boundingBox.min_y

  const texture = textureId
    ? Textures.getTexture(textureId)
    : device.createTexture({
        label: 'texture cache',
        format: presentationFormat,
        usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
        size: [width, height],
      })

  const encoder = device.createCommandEncoder()

  const multisampleTexture = getMultisampleTexture(device, width, height, presentationFormat)
  const descriptor: GPURenderPassDescriptor = {
    label: 'texture cache pass',
    colorAttachments: [
      {
        view: multisampleTexture.createView(),
        resolveTarget: texture.createView(),
        clearValue: [0, 0, 0, 1],
        loadOp: 'clear',
        storeOp: 'store',
      },
    ],
  }

  const pass = encoder.beginRenderPass(descriptor)
  updateRenderPass(pass)
  const ortho = mat4.ortho(
    boundingBox.min_x, // left
    boundingBox.min_x + width, // right
    boundingBox.min_y, // bottom
    boundingBox.min_y + height, // top
    1, // near
    -1 // far
  )
  const scaling = mat4.scaling([1, -1, 1]) // flip Y to make texture coords start(0,0) at bottom left corner
  const matrix = mat4.multiply(scaling, ortho)

  device.queue.writeBuffer(canvasMatrixBuffer, 0, matrix)

  endCacheCallback = () => {
    console.log('end cache')
    pass.end()
    const commandBuffer = encoder.finish()
    device.queue.submit([commandBuffer])
  }

  return Textures.setTexture(texture, textureId)
}
