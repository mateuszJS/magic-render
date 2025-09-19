import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

export default function getComputeShape(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'computeShape shader',
    code: shaderCode,
  })

  const pipeline = device.createComputePipeline({
    label: 'computeShape pipeline',
    layout: 'auto',
    compute: {
      module: shaderModule,
    },
  })

  return function computeShape(
    passEncoder: GPUComputePassEncoder,
    curvesDataView: DataView<ArrayBuffer>,
    texture: GPUTexture
  ) {
    const curvesBuffer = device.createBuffer({
      label: 'computeShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    delayedDestroy(curvesBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: texture.createView() },
        { binding: 1, resource: { buffer: curvesBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.dispatchWorkgroups(texture.width, texture.height)
  }
}
