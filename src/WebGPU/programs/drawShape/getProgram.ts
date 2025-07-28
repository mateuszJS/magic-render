import shaderCode from './shader.wgsl'

export interface CubicBezier {
  p0: { x: number; y: number }
  p1: { x: number; y: number }
  p2: { x: number; y: number }
  p3: { x: number; y: number }
}

export interface ShapeVertex {
  position: [number, number]
  color: [number, number, number, number]
}

export default function getDrawShape(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  canvasMatrixBuffer: GPUBuffer
) {
  const shaderModule = device.createShaderModule({
    label: 'drawShape shader',
    code: shaderCode,
  })

  const uniformBuffer = device.createBuffer({
    label: 'drawShape uniforms',
    size: 8 + 4 + 4 + 4, // vec2 + u32 + f32 + padding
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  let curvesBuffer: GPUBuffer | null = null
  let vertexBuffer: GPUBuffer | null = null
  let indexBuffer: GPUBuffer | null = null

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
          arrayStride: 6 * 4, // position (2) + color (4)
          attributes: [
            {
              shaderLocation: 0,
              offset: 0,
              format: 'float32x2', // position
            },
            {
              shaderLocation: 1,
              offset: 2 * 4,
              format: 'float32x4', // color
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
    primitive: {
      topology: 'triangle-list',
    },
    multisample: {
      count: 4,
    },
  })

  let bindGroup: GPUBindGroup | null = null

  function createBuffers(vertices: ShapeVertex[], curves: CubicBezier[]) {
    // Create vertex buffer
    const vertexData = new Float32Array(vertices.length * 6)
    for (let i = 0; i < vertices.length; i++) {
      const vertex = vertices[i]
      const offset = i * 6
      vertexData[offset] = vertex.position[0]
      vertexData[offset + 1] = vertex.position[1]
      vertexData[offset + 2] = vertex.color[0]
      vertexData[offset + 3] = vertex.color[1]
      vertexData[offset + 4] = vertex.color[2]
      vertexData[offset + 5] = vertex.color[3]
    }

    if (vertexBuffer) vertexBuffer.destroy()
    vertexBuffer = device.createBuffer({
      label: 'drawShape vertex buffer',
      size: vertexData.byteLength,
      usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(vertexBuffer, 0, vertexData)

    // Create curves buffer
    const curvesData = new Float32Array(curves.length * 8) // 4 points * 2 components each
    for (let i = 0; i < curves.length; i++) {
      const curve = curves[i]
      const offset = i * 8
      curvesData[offset] = curve.p0.x
      curvesData[offset + 1] = curve.p0.y
      curvesData[offset + 2] = curve.p1.x
      curvesData[offset + 3] = curve.p1.y
      curvesData[offset + 4] = curve.p2.x
      curvesData[offset + 5] = curve.p2.y
      curvesData[offset + 6] = curve.p3.x
      curvesData[offset + 7] = curve.p3.y
    }

    if (curvesBuffer) curvesBuffer.destroy()
    curvesBuffer = device.createBuffer({
      label: 'drawShape curves buffer',
      size: Math.max(curvesData.byteLength, 16), // Minimum size for empty buffer
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    if (curvesData.byteLength > 0) {
      device.queue.writeBuffer(curvesBuffer, 0, curvesData)
    }

    // Create indices for triangles (assuming quad)
    const indices = new Uint16Array([0, 1, 2, 2, 3, 0])
    if (indexBuffer) indexBuffer.destroy()
    indexBuffer = device.createBuffer({
      label: 'drawShape index buffer',
      size: indices.byteLength,
      usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(indexBuffer, 0, indices)

    // Create bind group
    bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: bindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: uniformBuffer },
        },
        {
          binding: 1,
          resource: { buffer: curvesBuffer },
        },
        {
          binding: 2,
          resource: { buffer: canvasMatrixBuffer },
        },
      ],
    })
  }

  return function drawShape(
    passEncoder: GPURenderPassEncoder,
    vertices: ShapeVertex[],
    curves: CubicBezier[],
    canvasSize: [number, number],
    strokeWidth: number = 0
  ) {
    if (vertices.length === 0) return

    createBuffers(vertices, curves)

    // Update uniforms
    const uniformData = new ArrayBuffer(8 + 4 + 4 + 4) // vec2 + u32 + f32 + padding
    const uniformView = new DataView(uniformData)

    // Canvas size
    uniformView.setFloat32(0, canvasSize[0], true)
    uniformView.setFloat32(4, canvasSize[1], true)

    // Number of curves
    uniformView.setUint32(8, curves.length, true)

    // Stroke width
    uniformView.setFloat32(12, strokeWidth, true)

    device.queue.writeBuffer(uniformBuffer, 0, uniformData)

    passEncoder.setPipeline(renderPipeline)
    passEncoder.setBindGroup(0, bindGroup!)
    passEncoder.setVertexBuffer(0, vertexBuffer!)
    passEncoder.setIndexBuffer(indexBuffer!, 'uint16')
    passEncoder.drawIndexed(6, 1, 0, 0, 0) // Draw quad
  }
}
