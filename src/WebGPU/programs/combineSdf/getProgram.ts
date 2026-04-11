import clamp from 'utils/clamp'
import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

export default function getCombineSdf(device: GPUDevice) {
  const shaderModule = device.createShaderModule({
    label: 'combineSdf shader',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'combineSDF pipeline',
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
    depthStencil: {
      depthWriteEnabled: true,
      depthCompare: 'greater',
      format: 'depth24plus',
    },
  })

  return function combineSdf(
    passEncoder: GPURenderPassEncoder,
    destTex: GPUTexture,
    sourceTex: GPUTexture,
    uniformData: DataView<ArrayBuffer>, // placement + initial_t
    curvesDataView: DataView<ArrayBuffer>
  ) {
    const curvesBuffer = device.createBuffer({
      label: 'renderShapeSdf curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    delayedDestroy(curvesBuffer)

    const uniformBuffer = device.createBuffer({
      label: 'combine sdf uniform buffer',
      size: uniformData.byteLength,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, uniformData)
    delayedDestroy(uniformBuffer)

    const startX = uniformData.getFloat32(0 * 4, true)
    const startY = uniformData.getFloat32(1 * 4, true)
    const sizeX = uniformData.getFloat32(2 * 4, true)
    const sizeY = uniformData.getFloat32(3 * 4, true)
    const scissorX = Math.max(0, Math.floor(startX))
    const scissorY = Math.max(0, Math.floor(startY))
    const scissorW = clamp(Math.ceil(startX + sizeX) - scissorX, 1, destTex.width - scissorX)
    const scissorH = clamp(Math.ceil(startY + sizeY) - scissorY, 1, destTex.height - scissorY)

    passEncoder.setPipeline(pipeline)
    passEncoder.setScissorRect(scissorX, scissorY, scissorW, scissorH)

    const bindGroup = device.createBindGroup({
      label: 'combineSdf bind group',
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: sourceTex.createView() },
        { binding: 1, resource: { buffer: uniformBuffer } },
        { binding: 2, resource: { buffer: curvesBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.draw(6)
  }
}
