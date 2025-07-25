import shaderCode from './shader.wgsl'

const INSTANCE_STRIDE =
  4 * 3 /* positon */ + 1 /* color */ + 3 /* value of roudned corner  for each of three positions */

export default function getProgram(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  matrixBuffer: GPUBuffer
) {
  const module = device.createShaderModule({
    label: 'draw triangle module',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'draw triangle pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: INSTANCE_STRIDE * 4, // The size in bytes for one instance's data
          stepMode: 'instance',
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // position 0
            { shaderLocation: 1, offset: 16, format: 'float32x4' }, // position 1
            { shaderLocation: 2, offset: 16 + 16, format: 'float32x4' }, // position 2
            { shaderLocation: 3, offset: 16 + 16 + 16, format: 'unorm8x4' }, // color 'rgba8unorm'
            { shaderLocation: 4, offset: 16 + 16 + 16 + 4, format: 'float32x3' }, // rounded corner values
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

  // Cache bind group for this program (no texture needed)
  const cachedBindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [{ binding: 0, resource: { buffer: matrixBuffer } }],
  })

  return function drawTriangle(
    pass: GPURenderPassEncoder,
    vertexData: ArrayBufferLike,
    vertexDataOffset = 0,
    vertexDataSize = 0
  ) {
    const numInstances = vertexDataSize / (4 * INSTANCE_STRIDE)

    const vertexBuffer = device.createBuffer({
      label: 'draw triangle - vertex buffer',
      size: vertexDataSize,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData, vertexDataOffset, vertexDataSize)

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)
    pass.setBindGroup(0, cachedBindGroup)
    pass.draw(3, numInstances)
  }
}
