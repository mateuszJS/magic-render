import shaderCode from './shader.wgsl'

export default function getComputeShape(device: GPUDevice, buffersToDestroy: GPUBuffer[]) {
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

  return function computeSDF(
    passEncoder: GPUComputePassEncoder,
    curvesDataView: DataView,
    distanceScaleFactor: number,
    texture: GPUTexture
  ) {
    const curvesBuffer = device.createBuffer({
      label: 'computeShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    buffersToDestroy.push(curvesBuffer)

    const uniformBuffer = device.createBuffer({
      label: 'computeShape uniform buffer',
      size: 4,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, new Float32Array([distanceScaleFactor]))
    buffersToDestroy.push(uniformBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: texture.createView() },
        { binding: 1, resource: { buffer: curvesBuffer } },
        { binding: 2, resource: { buffer: uniformBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.dispatchWorkgroups(texture.width, texture.height)
  }
}
