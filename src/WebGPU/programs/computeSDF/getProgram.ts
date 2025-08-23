import shaderCode from './shader.wgsl'

export default function getComputeSDF(device: GPUDevice, buffersToDestroy: GPUBuffer[]) {
  const shaderModule = device.createShaderModule({
    label: 'compute SDF shader',
    code: shaderCode,
  })

  const pipeline = device.createComputePipeline({
    label: 'compute SDF pipeline',
    layout: 'auto',
    compute: {
      module: shaderModule,
    },
  })

  return function drawShape(
    passEncoder: GPUComputePassEncoder,
    curvesDataView: DataView,
    texture: GPUTexture
  ) {
    const curvesBuffer = device.createBuffer({
      label: 'drawShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    buffersToDestroy.push(curvesBuffer)

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
