import { canvasMatrix } from '../initPrograms'
import shaderCode from './shader.wgsl'

const STRIDE_BYTES = 4 * 4
export default function getProgram(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  const module = device.createShaderModule({
    label: 'draw texture module',
    code: shaderCode,
  })

  const sampler = device.createSampler({
    minFilter: 'linear',
    magFilter: 'linear',
  })

  const pipeline = device.createRenderPipeline({
    label: 'draw texture pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE_BYTES,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // destination(xy) and source (zw) positions
          ] as const,
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [
        {
          format: presentationFormat,
          blend: {
            color: {
              srcFactor: 'one',
              dstFactor: 'one-minus-src-alpha',
            },
            alpha: {
              srcFactor: 'one',
              dstFactor: 'one-minus-src-alpha',
            },
          },
        },
      ],
    },
    multisample: {
      count: 4,
    },
  })

  // Cache bind groups per texture to avoid recreating them
  const bindGroupCache = new WeakMap<GPUTexture, GPUBindGroup>()

  return function drawTexture(
    pass: GPURenderPassEncoder,
    vertexData: DataView<ArrayBuffer>,
    texture: GPUTexture
  ) {
    const numVertices = vertexData.byteLength / STRIDE_BYTES

    const vertexBuffer = device.createBuffer({
      label: 'draw texture - vertex buffer',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })

    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // Get or create bind group for this texture
    let bindGroup = bindGroupCache.get(texture)
    if (!bindGroup) {
      bindGroup = device.createBindGroup({
        layout: pipeline.getBindGroupLayout(0),
        entries: [
          { binding: 0, resource: { buffer: canvasMatrix.buffer } },
          { binding: 1, resource: sampler },
          { binding: 2, resource: texture.createView() },
        ],
      })
      bindGroupCache.set(texture, bindGroup)
    }

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)
    pass.setBindGroup(0, bindGroup)
    pass.draw(numVertices)
  }
}
