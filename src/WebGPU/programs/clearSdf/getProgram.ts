import shaderCode from './shader.wgsl'

const WORKING_GROUP_SIZE = [16, 4, 1]

export default function getClearSdf(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'fill texture with max float shader module',
    code: shaderCode.replace('$WORKING_GROUP_SIZE', WORKING_GROUP_SIZE.join(', ')),
  })

  const pipeline = device.createComputePipeline({
    layout: 'auto',
    compute: {
      module: shaderModule,
    },
  })

  return function clearSdf(passEncoder: GPUComputePassEncoder, texture: GPUTexture) {
    const bindGroup = device.createBindGroup({
      label: 'clearSdf bind group',
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        {
          binding: 0,
          resource: texture.createView(),
        },
      ],
    })

    passEncoder.setPipeline(pipeline)
    passEncoder.setBindGroup(0, bindGroup)

    passEncoder.dispatchWorkgroups(
      Math.ceil(texture.width / WORKING_GROUP_SIZE[0]),
      Math.ceil(texture.height / WORKING_GROUP_SIZE[1])
    )
  }
}
