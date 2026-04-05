import { delayedDestroy, canvasMatrix } from '../initPrograms'
import baseCode from './base.wgsl'
import baseTestCode from './base.test.wgsl'

export default function getDrawShape(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  fragmentShader: string,
  uniformSize: number,
  isTest: boolean,
  onCompilation?: (info: GPUCompilationInfo) => void
) {
  const shaderModule = device.createShaderModule({
    label: 'drawShape shader',
    code: baseCode.replace('${TEST}', isTest ? baseTestCode : '') + fragmentShader,
  })

  if (onCompilation) {
    shaderModule.getCompilationInfo().then(onCompilation)
  }

  const uniformBufferSize = uniformSize * 4

  const pipeline = device.createRenderPipeline({
    label: 'drawShape pipeline',
    layout: 'auto',
    vertex: {
      module: shaderModule,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: 4 * 4, // position (4)
          attributes: [
            {
              shaderLocation: 0,
              offset: 0,
              format: 'float32x4', // position
            },
          ],
        },
      ],
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs',
      targets: [
        {
          format: presentationFormat,
          blend: {
            color: {
              srcFactor: 'src-alpha',
              dstFactor: 'one-minus-src-alpha',
            },
            alpha: {
              srcFactor: 'one',
              dstFactor: 'one-minus-src-alpha',
            },
          },
        },
      ],
    },
    multisample: {
      count: 4,
    },
  })

  return function drawShape(
    passEncoder: GPURenderPassEncoder,
    sdfTexture: GPUTexture,
    boundingBoxDataView: DataView<ArrayBuffer>,
    uniformDataView: DataView<ArrayBuffer>,
    curvesDataView: DataView<ArrayBuffer>
  ) {
    // console.log('================curvesDataView')
    // for (let i = 0; i < curvesDataView.byteLength; i += 4) {
    //   console.log(curvesDataView.getFloat32(i, true))
    // }
    const boundBoxBuffer = device.createBuffer({
      label: 'drawShape vertex buffer',
      size: boundingBoxDataView.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(boundBoxBuffer, 0, boundingBoxDataView)
    delayedDestroy(boundBoxBuffer)

    const uniformBuffer = device.createBuffer({
      label: 'drawShape uniforms',
      size: uniformBufferSize,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(uniformBuffer, 0, uniformDataView)
    delayedDestroy(uniformBuffer)

    const curvesBuffer = device.createBuffer({
      label: 'computeShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    delayedDestroy(curvesBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: sdfTexture.createView() },
        { binding: 2, resource: { buffer: canvasMatrix.buffer } },
        { binding: 3, resource: { buffer: curvesBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.setVertexBuffer(0, boundBoxBuffer)
    passEncoder.draw(6) // Draw quad
  }
}
