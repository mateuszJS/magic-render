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

  // const bindGroupLayout = device.createBindGroupLayout({
  //   label: 'drawShape bind group layout',
  //   entries: [
  //     {
  //       binding: 0,
  //       visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
  //       buffer: { type: 'uniform' },
  //     },
  //     {
  //       binding: 1,
  //       visibility: GPUShaderStage.FRAGMENT,
  //       buffer: { type: 'read-only-storage' },
  //     },
  //     {
  //       binding: 2,
  //       visibility: GPUShaderStage.VERTEX,
  //       buffer: { type: 'uniform' },
  //     },
  //   ],
  // })

  const pipeline = device.createRenderPipeline({
    label: 'drawShape pipeline',
    layout: 'auto',
    vertex: {
      module: shaderModule,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: 4 * 4, // position (4)
          attributes: [
            {
              shaderLocation: 0,
              offset: 0,
              format: 'float32x4', // position
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
    sdfTexture: GPUTexture,
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

    const uniformBuffer = device.createBuffer({
      label: 'drawShape uniforms',
      size: uniformBufferSize,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, uniformDataView)
    buffersToDestroy.push(uniformBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: sdfTexture.createView() },
        { binding: 2, resource: { buffer: canvasMatrixBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.setVertexBuffer(0, boundBoxBuffer)
    passEncoder.draw(6) // Draw quad
  }
}
