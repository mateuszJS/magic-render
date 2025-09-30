import shaderCode from './shader.wgsl'

export default function getClearSdf(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'fill texture with max float shader module',
    code: shaderCode,
  })

  const pipeline = device.createComputePipeline({
    layout: 'auto',
    compute: {
      module: shaderModule,
    },
  })

  return function clearSdf(passEncoder: GPUComputePassEncoder, texture: GPUTexture) {
    const bindGroup = device.createBindGroup({
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

    // const workgroupsX = Math.ceil(width / 8 )
    // const workgroupsY = Math.ceil(height / 8)
    passEncoder.dispatchWorkgroups(texture.width, texture.height)
  }
}
