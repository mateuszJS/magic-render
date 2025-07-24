import shaderCode from './shader.wgsl'

const STRIDE = 4 + 1

export default function getProgram(device: GPUDevice, matrixBuffer: GPUBuffer) {
  const module = device.createShaderModule({
    label: 'pick triangle module',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'pick triangle pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE * 4,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // destination position
            { shaderLocation: 1, offset: 16, format: 'float32' }, // id
          ] as const,
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [
        {
          format: 'r32uint',
          // blend: {
          //   color: {
          //     srcFactor: 'one',
          //     dstFactor: 'one-minus-src-alpha'
          //   },
          //   alpha: {
          //     srcFactor: 'one',
          //     dstFactor: 'one-minus-src-alpha'
          //   },
          // },
        },
      ],
    },
    // depthStencil: {
    //   depthWriteEnabled: true,
    //   depthCompare: 'less',
    //   format: 'depth24plus',
    // },
  })

  // Cache bind group for this program (no texture needed)
  let cachedBindGroup: GPUBindGroup | null = null

  return function pickTriangle(
    pass: GPURenderPassEncoder,
    vertexData: Float32Array<ArrayBufferLike>
  ) {
    const numVertices = (vertexData.length / STRIDE) | 0
    const vertexBuffer = device.createBuffer({
      label: 'pick triangle vertex buffer vertices',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // Get or create bind group for this program
    if (!cachedBindGroup) {
      cachedBindGroup = device.createBindGroup({
        layout: pipeline.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: { buffer: matrixBuffer } }],
      })
    }

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)
    pass.setBindGroup(0, cachedBindGroup)
    pass.draw(numVertices)
  }
}
