import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

const WORKING_GROUP_SIZE = [16, 4, 1]

export default function getCombineSdf(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'combineSdf shader',
    code: shaderCode.replace('$WORKING_GROUP_SIZE', WORKING_GROUP_SIZE.join(', ')),
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
    placementData: DataView<ArrayBuffer> // [placement_start_x, placement_start_y, placement_size_x, placement_size_y]
  ) {
    const uniformBuffer = device.createBuffer({
      label: 'combine sdf uniform buffer',
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

    const startX = placementData.getFloat32(0 * 4, true)
    const startY = placementData.getFloat32(1 * 4, true)
    const sizeX = placementData.getFloat32(2 * 4, true)
    const sizeY = placementData.getFloat32(3 * 4, true)

    const width = Math.max(0, Math.ceil(startX + sizeX) - Math.floor(startX))
    const height = Math.max(0, Math.ceil(startY + sizeY) - Math.floor(startY))

    passEncoder.dispatchWorkgroups(
      Math.ceil(width / WORKING_GROUP_SIZE[0]),
      Math.ceil(height / WORKING_GROUP_SIZE[1])
    )
  }
}
