import shaderCode from './shader.wgsl'
import getBoundingBox from './getBoundingBox'

export default function getDrawShape(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  canvasMatrixBuffer: GPUBuffer
) {
  const shaderModule = device.createShaderModule({
    label: 'drawShape shader',
    code: shaderCode,
  })

  const uniformBufferSize =
    (1 /*stroke width*/ + 4 /*stroke color*/ + 4 /*fill color*/ + /*padding*/ 3) * 4

  const uniformBuffer = device.createBuffer({
    label: 'drawShape uniforms',
    size: uniformBufferSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  // Update uniforms
  const uniformValues = new Float32Array(uniformBufferSize / 4)

  // offsets to the various uniform values in float32 indices
  let start = 0
  let end = 4 /* 1 of stroke  + 3 of padding */
  const strokeWidthValue = uniformValues.subarray(start, (start = end))

  end += 4
  const strokeColorValue = uniformValues.subarray(start, (start = end))

  end += 4
  const fillColorValue = uniformValues.subarray(start, (start = end))

  const bindGroupLayout = device.createBindGroupLayout({
    label: 'drawShape bind group layout',
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: 'uniform' },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: { type: 'read-only-storage' },
      },
      {
        binding: 2,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: 'uniform' },
      },
    ],
  })

  const renderPipeline = device.createRenderPipeline({
    label: 'drawShape pipeline',
    layout: device.createPipelineLayout({
      bindGroupLayouts: [bindGroupLayout],
    }),
    vertex: {
      module: shaderModule,
      entryPoint: 'vs',
      buffers: [
        {
          arrayStride: 2 * 4, // position (2) + color (4)
          attributes: [
            {
              shaderLocation: 0,
              offset: 0,
              format: 'float32x2', // position
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

  return function drawShape(passEncoder: GPURenderPassEncoder, curves: Point[]) {
    const strokeWidth = 20
    const boundingBox = getBoundingBox(curves, strokeWidth / 2)

    // Create curves buffer
    const curvesData = new Float32Array(curves.length * 2) // x y per point

    for (let i = 0; i < curves.length; i++) {
      const point = curves[i]
      const offset = i * 2
      curvesData[offset + 0] = point.x
      curvesData[offset + 1] = point.y
    }

    // Create vertex buffer
    // prettier-ignore
    const vertexData = new Float32Array([
      boundingBox[0].x, boundingBox[0].y,
      boundingBox[1].x, boundingBox[1].y,
      boundingBox[2].x, boundingBox[2].y,
      boundingBox[2].x, boundingBox[2].y,
      boundingBox[3].x, boundingBox[3].y,
      boundingBox[0].x, boundingBox[0].y,
    ])

    const vertexBuffer = device.createBuffer({
      label: 'drawShape vertex buffer',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    const curvesBuffer = device.createBuffer({
      label: 'drawShape curves buffer',
      size: curvesData.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesData)

    strokeWidthValue.set([strokeWidth])
    strokeColorValue.set([1, 0, 0, 1]) // Red stroke color
    fillColorValue.set([0, 1, 0, 1]) // Green fill color
    device.queue.writeBuffer(uniformBuffer, 0, uniformValues)

    passEncoder.setPipeline(renderPipeline)

    const bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: bindGroupLayout,
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: { buffer: curvesBuffer } },
        { binding: 2, resource: { buffer: canvasMatrixBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.setVertexBuffer(0, vertexBuffer)
    passEncoder.draw(6) // Draw quad
  }
}
