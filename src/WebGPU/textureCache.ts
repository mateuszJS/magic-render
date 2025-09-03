import { canvasMatrix } from 'WebGPU/programs/initPrograms'
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
  encoder: GPUCommandEncoder,
  textureId: number,
  boundingBox: BoundingBox,
  outputWidth: number,
  outputHeight: number
): void {
  const width = boundingBox.max_x - boundingBox.min_x
  const height = boundingBox.max_y - boundingBox.min_y

  let texture = Textures.getOptionTexture(textureId)
  const canReuseTexture =
    texture &&
    Math.abs(texture.width - outputWidth) <= Number.EPSILON &&
    Math.abs(texture.height - outputHeight) <= Number.EPSILON

  if (!canReuseTexture) {
    texture?.destroy()
    texture = device.createTexture({
      label: 'texture cache',
      format: presentationFormat,
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
      size: [outputWidth, outputHeight],
    })
  }

  if (!texture) {
    throw new Error('Failed to create texture for cache')
  }

  const multisampleTexture = getMultisampleTexture(
    device,
    outputWidth,
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
        // clearValue: [0.5, 0, 0.5, 0],
      },
    ],
  }
  const pass = encoder.beginRenderPass(descriptor)
  updateRenderPass(pass)
  const matrixBuffer = device.createBuffer({
    label: 'texture cache - matrix buffer',
    size: 16 * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })
  const matrix = mat4.ortho(
    boundingBox.min_x, // left
    boundingBox.min_x + width, // right
    boundingBox.min_y + height, // bottom
    boundingBox.min_y, // top, yes top and bottom and reversed on purpose to make texture start at bottom-left corner
    1, // near
    -1 // far
  )

  device.queue.writeBuffer(matrixBuffer, 0, matrix)

  const canvasMatrixCopy = canvasMatrix.buffer
  canvasMatrix.buffer = matrixBuffer

  endCacheCallback = () => {
    pass.end()
    canvasMatrix.buffer = canvasMatrixCopy
  }

  Textures.setCacheTexture(textureId, texture)
}
