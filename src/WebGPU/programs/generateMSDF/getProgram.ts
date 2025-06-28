import { CubicBezier } from 'types'
import shaderCode from './shader.wgsl'

// Generate Multi-Channel Shape Decomposition Distance Field

const STRIDE = 4

export default function getProgram(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  const module = device.createShaderModule({
    label: 'generate MSDF module',
    code: shaderCode,
  })

  const pipeline = device.createRenderPipeline({
    label: 'generate MSDF pipeline',
    layout: 'auto',
    vertex: {
      module,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: STRIDE * 4,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x4' }, // destination position
          ] as const,
        },
      ],
    },
    fragment: {
      module,
      entryPoint: 'fs',
      targets: [
        {
          format: presentationFormat,
        },
      ],
    },
  })

  const uniformBufferSize = 16 /*projection matrix*/ * 4
  const uniformBuffer = device.createBuffer({
    label: 'uniforms',
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  const uniformValues = new Float32Array(uniformBufferSize / 4)
  const kMatrixOffset = 0
  const matrixValue = uniformValues.subarray(kMatrixOffset, kMatrixOffset + 16)

  return function drawMSDF(
    pass: GPURenderPassEncoder,
    worldProjectionMatrix: Float32Array,
    vertexData: Float32Array<ArrayBufferLike>,
    cubicBezierCurves: CubicBezier[]
  ) {
    const numVertices = (vertexData.length / STRIDE) | 0
    const vertexBuffer = device.createBuffer({
      label: 'vertex buffer vertices',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // storage buffer
    const quadBezierCurverSize = 2 /* x,y */ * 4 /* 4 points per curve */ * 4 /* 4 bytes per f32 */
    const curvesStorageBufferSize = quadBezierCurverSize * cubicBezierCurves.length
    const curvesStorageBuffer = device.createBuffer({
      label: 'quad bezier curves storage',
      size: curvesStorageBufferSize,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })

    const curveStorageValues = new Float32Array(curvesStorageBufferSize / 4)
    cubicBezierCurves.forEach((curve, i) => {
      const staticOffset = i * (quadBezierCurverSize / 4)
      curveStorageValues.set(
        [
          curve[0].x,
          curve[0].y,
          curve[1].x,
          curve[1].y,
          curve[2].x,
          curve[2].y,
          curve[3].x,
          curve[3].y,
        ],
        staticOffset
      )
    })
    device.queue.writeBuffer(curvesStorageBuffer, 0, curveStorageValues)

    // bind group should be pre-created and reuse instead of constantly initialized
    const bindGroup = device.createBindGroup({
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: { buffer: curvesStorageBuffer } },
      ],
    })

    pass.setPipeline(pipeline)
    pass.setVertexBuffer(0, vertexBuffer)

    matrixValue.set(worldProjectionMatrix)

    device.queue.writeBuffer(uniformBuffer, 0, uniformValues)

    pass.setBindGroup(0, bindGroup)
    pass.draw(numVertices)
  }
}
