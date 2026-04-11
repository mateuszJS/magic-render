import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

export default function getComputeShape(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'renderShapeSdf shader',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'renderShapeSdf pipeline',
    layout: 'auto',
    vertex: {
      module: shaderModule,
      entryPoint: 'vs',
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs',
      targets: [{ format: 'r32float' }],
    },
  })

  return function computeShape(
    commandEncoder: GPUCommandEncoder,
    curvesDataView: DataView<ArrayBuffer>,
    texture: GPUTexture
  ) {
    const curvesBuffer = device.createBuffer({
      label: 'renderShapeSdf curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    delayedDestroy(curvesBuffer)

    const passEncoder = commandEncoder.beginRenderPass({
      label: 'renderShapeSdf render pass',
      colorAttachments: [
        {
          view: texture.createView(),
          loadOp: 'clear',
          clearValue: { r: 0, g: 0, b: 0, a: 1 },
          storeOp: 'store',
        },
      ],
    })

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [{ binding: 0, resource: { buffer: curvesBuffer } }],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.draw(6)
    passEncoder.end()
  }
}
