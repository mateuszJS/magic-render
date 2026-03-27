import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

const WORKING_GROUP_SIZE = [16, 4, 1]

export default function getComputeShape(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'computeShape shader',
    code: shaderCode.replace('$WORKING_GROUP_SIZE', WORKING_GROUP_SIZE.join(', ')),
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
    passEncoder.dispatchWorkgroups(
      Math.ceil(texture.width / WORKING_GROUP_SIZE[0]),
      Math.ceil(texture.height / WORKING_GROUP_SIZE[1])
    )
  }
}
