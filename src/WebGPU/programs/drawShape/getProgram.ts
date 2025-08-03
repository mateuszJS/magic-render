import shaderCode from './shader.wgsl'

export default function getDrawShape(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  canvasMatrixBuffer: GPUBuffer,
  buffersToDestroy: GPUBuffer[]
) {
  const shaderModule = device.createShaderModule({
    label: 'drawShape shader',
    code: shaderCode,
  })

  const uniformBufferSize =
    (1 /*stroke width*/ + 4 /*stroke color*/ + 4 /*fill color*/ + /*padding*/ 3) * 4

  const bindGroupLayout = device.createBindGroupLayout({
    label: 'drawShape bind group layout',
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: 'uniform' },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: { type: 'read-only-storage' },
      },
      {
        binding: 2,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: 'uniform' },
      },
    ],
  })

  const renderPipeline = device.createRenderPipeline({
    label: 'drawShape pipeline',
    layout: device.createPipelineLayout({
      bindGroupLayouts: [bindGroupLayout],
    }),
    vertex: {
      module: shaderModule,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: 2 * 4, // position (2) + color (4)
          attributes: [
            {
              shaderLocation: 0,
              offset: 0,
              format: 'float32x2', // position
            },
          ],
        },
      ],
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs',
      targets: [
        {
          format: presentationFormat,
          blend: {
            color: {
              srcFactor: 'src-alpha',
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

  return function drawShape(
    passEncoder: GPURenderPassEncoder,
    curvesDataView: DataView,
    boundingBoxDataView: DataView,
    uniformDataView: DataView
  ) {
    const boundBoxBuffer = device.createBuffer({
      label: 'drawShape vertex buffer',
      size: boundingBoxDataView.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(boundBoxBuffer, 0, boundingBoxDataView)
    buffersToDestroy.push(boundBoxBuffer)

    const curvesBuffer = device.createBuffer({
      label: 'drawShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    buffersToDestroy.push(curvesBuffer)

    const uniformBuffer = device.createBuffer({
      label: 'drawShape uniforms',
      size: uniformBufferSize,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, uniformDataView)
    buffersToDestroy.push(uniformBuffer)

    passEncoder.setPipeline(renderPipeline)

    const bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: bindGroupLayout,
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: { buffer: curvesBuffer } },
        { binding: 2, resource: { buffer: canvasMatrixBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.setVertexBuffer(0, boundBoxBuffer)
    passEncoder.draw(6) // Draw quad
  }
}
