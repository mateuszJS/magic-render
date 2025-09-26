import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

export default function getCombineSdf(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'combineSdf shader',
    code: shaderCode,
  })

  const pipeline = device.createComputePipeline({
    label: 'combineSdf pipeline',
    layout: 'auto',
    compute: {
      module: shaderModule,
    },
  })

  return function combineSdf(
    passEncoder: GPUComputePassEncoder,
    destinationTex: GPUTexture,
    sourceTex: GPUTexture,
    computeDepthTex: GPUTexture,
    placementData: DataView<ArrayBuffer> // [placement_start_x, placement_start_y, placement_end_x, placement_end_y]
  ) {
    const uniformBuffer = device.createBuffer({
      label: 'computeShape curves buffer',
      size: placementData.byteLength,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, placementData)
    delayedDestroy(uniformBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: destinationTex.createView() },
        { binding: 1, resource: sourceTex.createView() },
        { binding: 2, resource: computeDepthTex.createView() },
        { binding: 3, resource: { buffer: uniformBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    const width = placementData.getFloat32(2 * 4, true) - placementData.getFloat32(0 * 4, true)
    const height = placementData.getFloat32(3 * 4, true) - placementData.getFloat32(1 * 4, true)

    passEncoder.dispatchWorkgroups(width, height)
  }
}
