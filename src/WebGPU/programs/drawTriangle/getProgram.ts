import shaderCode from './shader.wgsl'

const INSTANCE_STRIDE =
  4 * 3 /* positon */ + 4 /* color */ + 3 /* value of roudned corner  for each of three positions */

export default function getProgram(device: GPUDevice, presentationFormat: GPUTextureFormat) {
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
            { shaderLocation: 3, offset: 16 + 16 + 16, format: 'float32x4' }, // color
            { shaderLocation: 4, offset: 16 + 16 + 16 + 16, format: 'float32x3' }, // rounded corner values
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
  })

  const uniformBufferSize = 16 /*projection matrix*/ * 4
  const uniformBuffer = device.createBuffer({
    label: 'uniforms',
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  const uniformValues = new Float32Array(uniformBufferSize / 4)
  const kMatrixOffset = 0
  const matrixValue = uniformValues.subarray(kMatrixOffset, kMatrixOffset + 16)

  return function drawTriangle(
    pass: GPURenderPassEncoder,
    worldProjectionMatrix: Float32Array,
    vertexData: Float32Array<ArrayBufferLike>
  ) {
    // console.log('worldProjectionMatrix', worldProjectionMatrix)
    const numInstances = vertexData.length / INSTANCE_STRIDE
    const numVertices = 3 // For instancing, this is the vertex count for a single instance

    const vertexBuffer = device.createBuffer({
      label: 'vertex buffer vertices',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // bind group should be pre-created and reuse instead of constantly initialized
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [{ binding: 0, resource: { buffer: uniformBuffer } }],
    })

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)

    matrixValue.set(worldProjectionMatrix)

    device.queue.writeBuffer(uniformBuffer, 0, uniformValues)

    pass.setBindGroup(0, bindGroup)
    pass.draw(numVertices, numInstances)
  }
}
