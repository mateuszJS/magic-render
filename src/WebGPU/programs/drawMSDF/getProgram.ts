import shaderCode from './shader.wgsl'

const INSTANCE_STRIDE =
  3 /*3 verticies*/ * 4 /*destination(xy) and texture coords(zw) */ + 1 /*color*/

export default function getProgram(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  matrixBuffer: GPUBuffer
) {
  const module = device.createShaderModule({
    label: 'draw msdf module',
    code: shaderCode,
  })

  const sampler = device.createSampler({
    minFilter: 'linear',
    magFilter: 'linear',
  })

  const pipeline = device.createRenderPipeline({
    label: 'draw msdf pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: INSTANCE_STRIDE * 4,
          stepMode: 'instance',
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // p0
            { shaderLocation: 1, offset: 16, format: 'float32x4' }, // p1
            { shaderLocation: 2, offset: 16 + 16, format: 'float32x4' }, // p2
            { shaderLocation: 3, offset: 16 + 16 + 16, format: 'unorm8x4' }, // color
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

  const bindGroupCache = new WeakMap<GPUTexture, GPUBindGroup>()

  return function drawMSDF(pass: GPURenderPassEncoder, vertexData: DataView, texture: GPUTexture) {
    const numInstances = vertexData.byteLength / (4 * INSTANCE_STRIDE)

    const vertexBuffer = device.createBuffer({
      label: 'draw msdf - vertex buffer',
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
    pass.draw(3, numInstances)
  }
}
