import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

export default function getDrawShape(device: GPUDevice, matrixBuffer: GPUBuffer) {
  const module = device.createShaderModule({
    label: 'pickShape shader',
    code: shaderCode,
  })

  const STRIDE = (4 /*position */ + 4) /*id*/ * 4

  const pipeline = device.createRenderPipeline({
    label: 'pickShape pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // position
            { shaderLocation: 1, offset: 16, format: 'uint32x4' }, // id
          ],
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [
        {
          format: 'rgba32uint',
        },
      ],
    },
  })

  return function pickShape(
    pass: GPURenderPassEncoder,
    vertexData: DataView<ArrayBuffer>,
    uniformData: DataView<ArrayBuffer>,
    sdfTexture: GPUTexture
  ) {
    if (true == true) {
      return
    }
    const numVertices = vertexData.byteLength / STRIDE

    const uniformBuffer = device.createBuffer({
      label: 'pickShape uniforms',
      size: uniformData.byteLength,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, uniformData)
    delayedDestroy(uniformBuffer)

    const vertexBuffer = device.createBuffer({
      label: 'pick texture - vertex buffer',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)
    delayedDestroy(vertexBuffer)

    // Get or create bind group for this texture
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: matrixBuffer } },
        { binding: 1, resource: { buffer: uniformBuffer } },
        { binding: 2, resource: sdfTexture.createView() },
      ],
    })

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)
    pass.setBindGroup(0, bindGroup)
    pass.draw(numVertices)
  }
}
