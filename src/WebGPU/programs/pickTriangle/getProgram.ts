import { delayedDestroy } from '../initPrograms'
import shaderCode from './shader.wgsl'

const INSTANCE_STRIDE =
  4 * 3 /* positon */ + 4 /* id */ + 3 /* value of roudned corner  for each of three positions */

export default function getProgram(device: GPUDevice, matrixBuffer: GPUBuffer) {
  const module = device.createShaderModule({
    label: 'pick triangle module',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'pick triangle pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: INSTANCE_STRIDE * 4,
          stepMode: 'instance',
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // position 0
            { shaderLocation: 1, offset: 16, format: 'float32x4' }, // position 1
            { shaderLocation: 2, offset: 16 + 16, format: 'float32x4' }, // position 2
            { shaderLocation: 3, offset: 16 + 16 + 16, format: 'uint32x4' }, // id
            { shaderLocation: 4, offset: 16 + 16 + 16 + 16, format: 'float32x3' }, // rounded corner values
          ] as const,
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [
        {
          format: 'rgba32uint',
        },
      ],
    },
  })

  // Cache bind group for this program (no texture needed)
  let cachedBindGroup: GPUBindGroup | null = null

  return function pickTriangle(pass: GPURenderPassEncoder, vertexData: DataView<ArrayBuffer>) {
    const numInstances = vertexData.byteLength / (4 * INSTANCE_STRIDE)

    const vertexBuffer = device.createBuffer({
      label: 'pick triangle vertex buffer vertices',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    delayedDestroy(vertexBuffer)
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // Get or create bind group for this program
    if (!cachedBindGroup) {
      cachedBindGroup = device.createBindGroup({
        layout: pipeline.getBindGroupLayout(0),
        entries: [{ binding: 0, resource: { buffer: matrixBuffer } }],
      })
    }

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)
    pass.setBindGroup(0, cachedBindGroup)
    pass.draw(3, numInstances)
  }
}
