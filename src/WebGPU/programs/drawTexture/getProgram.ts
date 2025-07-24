import shaderCode from './shader.wgsl'

const STRIDE = 4 + 2 // + 1 + 1 + 4

export default function getProgram(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  matrixBuffer: GPUBuffer
) {
  const module = device.createShaderModule({
    label: 'texture module',
    code: shaderCode,
  })

  const sampler = device.createSampler({
    minFilter: 'linear',
    magFilter: 'linear',
  })

  const pipeline = device.createRenderPipeline({
    label: 'texture pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE * 4,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // destination position
            { shaderLocation: 1, offset: 16, format: 'float32x2' }, // source position
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
    // depthStencil: {
    //   depthWriteEnabled: true,
    //   depthCompare: 'less',
    //   format: 'depth24plus',
    // },
  })

  // Cache bind groups per texture to avoid recreating them
  const bindGroupCache = new WeakMap<GPUTexture, GPUBindGroup>()

  return function drawTexture(
    pass: GPURenderPassEncoder,
    vertexData: Float32Array<ArrayBufferLike>,
    texture: GPUTexture
  ) {
    const numVertices = (vertexData.length / STRIDE) | 0

    const vertexBuffer = device.createBuffer({
      label: 'vertex buffer vertices',
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
          { binding: 0, resource: { buffer: matrixBuffer } },
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
