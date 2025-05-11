import shaderCode from "./shader.wgsl"
 

const STRIDE = 4 + 4// + 1 + 1 + 4

export default function getProgram(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat
) {
  const module = device.createShaderModule({
    label: 'draw triangle module',
    code: shaderCode
  })

  const pipeline = device.createRenderPipeline({
    label: 'draw triangle pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE * 4,
          attributes: [
            {shaderLocation: 0, offset: 0, format: 'float32x4'},  // destination position
            {shaderLocation: 1, offset: 16, format: 'float32x4'},  // color
          ] as const,
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [{
        format: presentationFormat,
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
      }],
    },
    // depthStencil: {
    //   depthWriteEnabled: true,
    //   depthCompare: 'less',
    //   format: 'depth24plus',
    // },
  })

  const uniformBufferSize = (
    16/*projection matrix*/
  ) * 4
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
    vertexData: Float32Array<ArrayBufferLike>,
  ) {
    const numVertices = vertexData.length / STRIDE | 0
    const vertexBuffer = device.createBuffer({
      label: 'vertex buffer vertices',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)


    // bind group should be pre-created and reuse instead of constantly initialized
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer }},
      ],
    })


    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)

    matrixValue.set(worldProjectionMatrix)

    device.queue.writeBuffer(uniformBuffer, 0, uniformValues)

    pass.setBindGroup(0, bindGroup)
    pass.draw(numVertices)
  }
}
