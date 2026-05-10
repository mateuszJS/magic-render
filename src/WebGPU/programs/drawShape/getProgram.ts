import { delayedDestroy, canvasMatrix } from '../initPrograms'
import baseCode from './base.wgsl'
import baseTestCode from './base.test.wgsl'
import bazierUtilsCode from '../bezier-utils.wgsl'

type DebugType = 'arrow' | 'digits' | 'none'

declare global {
  interface Window {
    setDebugType: (type: DebugType) => void
  }
}

let debugType: DebugType = (window.localStorage.debugType as DebugType | undefined) || 'none'
window.setDebugType = (type: DebugType) => {
  debugType = type
  window.localStorage.debugType = type
}

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
    code:
      baseCode.replace('${TEST}', isTest ? baseTestCode : '') + fragmentShader + bazierUtilsCode,
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

  // PathMetrics uniform layout (must match base.wgsl `struct PathMetrics`):
  //   off  0 : texture_size    vec2f  (dimensions in texels)
  //   off  8 : total_arc_len   f32
  //   off 12 : num_curves      u32
  //   off 16 : debug_scale     f32    (devicePixelRatio for debug overlay)
  //   off 20 : 12 bytes padding (struct rounded up to 32 for uniform align)
  const PATH_METRICS_BYTES = 32
  // Size of one cubic curve in `curves` storage buffer: 4 vec2f × 8 bytes.
  const CURVE_STRIDE_BYTES = 4 * 2 * 4

  return function drawShape(
    passEncoder: GPURenderPassEncoder,
    sdfTexture: GPUTexture,
    boundingBoxDataView: DataView<ArrayBuffer>,
    uniformDataView: DataView<ArrayBuffer>,
    curvesDataView: DataView<ArrayBuffer>,
    arcLengthsDataView: DataView<ArrayBuffer>,
    maxDistancesDataView: DataView<ArrayBuffer>
  ) {
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
      label: 'drawShape curves buffer',
      size: curvesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(curvesBuffer, 0, curvesDataView)
    delayedDestroy(curvesBuffer)

    const arcLengthsBuffer = device.createBuffer({
      label: 'drawShape arc lengths buffer',
      size: arcLengthsDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(arcLengthsBuffer, 0, arcLengthsDataView)
    delayedDestroy(arcLengthsBuffer)

    const maxDistancesBuffer = device.createBuffer({
      label: 'drawShape local distances buffer',
      size: maxDistancesDataView.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(maxDistancesBuffer, 0, maxDistancesDataView)
    delayedDestroy(maxDistancesBuffer)

    // Build the PathMetrics uniform from the data we already have.
    // `total_arc_len` is the last entry of arc_lengths (cumulative arc length
    // at end of last curve). `num_curves` is the curve count derived from
    // the curves storage buffer's byte length.
    const metricsArrayBuffer = new ArrayBuffer(PATH_METRICS_BYTES)
    const metricsF32 = new Float32Array(metricsArrayBuffer)
    const metricsU32 = new Uint32Array(metricsArrayBuffer)
    const totalArcLen =
      arcLengthsDataView.byteLength >= 4
        ? arcLengthsDataView.getFloat32(arcLengthsDataView.byteLength - 4, true)
        : 0
    const numCurves = (curvesDataView.byteLength / CURVE_STRIDE_BYTES) | 0
    metricsF32[0] = sdfTexture.width // texture_size.x
    metricsF32[1] = sdfTexture.height // texture_size.y
    metricsF32[2] = totalArcLen // total_arc_len
    metricsU32[3] = numCurves // num_curves
    // debug_scale: physical-pixels-per-CSS-pixel so the debug overlay's grid
    // cells and digit glyphs stay visually the same size on retina displays.
    metricsF32[4] = window.devicePixelRatio || 1
    // prettier-ignore
    metricsU32[5] = debugType === 'arrow'
      ? 1
      : debugType === 'digits'
        ? 2
        : 0 // debug_arrow

    const pathMetricsBuffer = device.createBuffer({
      label: 'drawShape path metrics',
      size: PATH_METRICS_BYTES,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    })
    device.queue.writeBuffer(pathMetricsBuffer, 0, metricsArrayBuffer)
    delayedDestroy(pathMetricsBuffer)

    passEncoder.setPipeline(pipeline)

    const bindGroup = device.createBindGroup({
      label: 'drawShape bind group',
      layout: pipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuffer } },
        { binding: 1, resource: sdfTexture.createView() },
        { binding: 2, resource: { buffer: canvasMatrix.buffer } },
        { binding: 3, resource: { buffer: curvesBuffer } },
        { binding: 4, resource: { buffer: arcLengthsBuffer } },
        { binding: 5, resource: { buffer: pathMetricsBuffer } },
        { binding: 6, resource: { buffer: maxDistancesBuffer } },
      ],
    })

    passEncoder.setBindGroup(0, bindGroup)
    passEncoder.setVertexBuffer(0, boundBoxBuffer)
    passEncoder.draw(6) // Draw quad
  }
}
