import shaderCode from './shader.wgsl'

const INSTANCE_STRIDE =
  3 /*3 verticies*/ * (4 /*destinatio position*/ + 2) /*source position*/ + 4 /*color*/

export default function getProgram(device: GPUDevice, presentationFormat: GPUTextureFormat) {
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
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // p0 destination position
            { shaderLocation: 1, offset: 16, format: 'float32x2' }, // p0 source position
            { shaderLocation: 2, offset: 16 + 8, format: 'float32x4' }, // p1 destination position
            { shaderLocation: 3, offset: 16 + 8 + 16, format: 'float32x2' }, // p1 source position
            { shaderLocation: 4, offset: 16 + 8 + 16 + 8, format: 'float32x4' }, // p2 destination position
            { shaderLocation: 5, offset: 16 + 8 + 16 + 8 + 16, format: 'float32x2' }, // p2 source position
            { shaderLocation: 6, offset: 16 + 8 + 16 + 8 + 16 + 8, format: 'float32x4' }, // color
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
    // depthStencil: {
    //   depthWriteEnabled: true,
    //   depthCompare: 'less',
    //   format: 'depth24plus',
    // },
  })

  const uniformBufferSize =
    (16 /*projection matrix*/ + 1 /*screen pixel distance*/ + 3) /*padding*/ * 4
  const uniformBuffer = device.createBuffer({
    label: 'draw msdf uniforms',
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  const uniformValues = new Float32Array(uniformBufferSize / 4)
  const kMatrixOffset = 0
  const matrixValue = uniformValues.subarray(kMatrixOffset, kMatrixOffset + 16)

  const kScreenPixelDistanceOffset = 16
  const screenPixelDistanceValue = uniformValues.subarray(
    kScreenPixelDistanceOffset,
    kScreenPixelDistanceOffset + 1
  )

  return function drawMSDF(
    pass: GPURenderPassEncoder,
    worldProjectionMatrix: Float32Array,
    vertexData: Float32Array,
    texture: GPUTexture
  ) {
    const numInstances = vertexData.length / INSTANCE_STRIDE

    const vertexBuffer = device.createBuffer({
      label: 'draw msdf - vertex buffer',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // bind group should be pre-created and reuse instead of constantly initialized
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: sampler },
        { binding: 2, resource: texture.createView() },
      ],
    })

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)

    matrixValue.set(worldProjectionMatrix)
    screenPixelDistanceValue.set([16.0]) // Set the screen pixel distance to 1.0 for now, can be adjusted later

    device.queue.writeBuffer(uniformBuffer, 0, uniformValues)

    pass.setBindGroup(0, bindGroup)
    pass.draw(3, numInstances)
  }
}
