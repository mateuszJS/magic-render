import shaderCode from './shader.wgsl'

const WORKING_GROUP_SIZE = [16, 4, 1] as const
const BYTES_PER_TEXEL = 16 // rgba32float: 4 channels × 4 bytes

let device: GPUDevice
let pipeline: GPUComputePipeline

const initPromise = (async () => {
  const adapter = await navigator.gpu.requestAdapter()
  if (!adapter) throw new Error('No GPU adapter in computeShape worker')
  device = await adapter.requestDevice()

  const shaderModule = device.createShaderModule({
    code: shaderCode.replace('$WORKING_GROUP_SIZE', WORKING_GROUP_SIZE.join(', ')),
  })
  pipeline = device.createComputePipeline({
    layout: 'auto',
    compute: { module: shaderModule },
  })
})()

self.onmessage = async (e: MessageEvent) => {
  try {
  await initPromise

  const { curvesData, width, height, id } = e.data as {
    curvesData: ArrayBuffer
    width: number
    height: number
    id: number
  }

  // bytesPerRow must be a multiple of 256
  const bytesPerRow = Math.ceil((width * BYTES_PER_TEXEL) / 256) * 256

  const texture = device.createTexture({
    size: [width, height],
    format: 'rgba32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.COPY_SRC,
  })

  const curvesBuffer = device.createBuffer({
    size: curvesData.byteLength,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  })
  device.queue.writeBuffer(curvesBuffer, 0, curvesData)

  const bindGroup = device.createBindGroup({
    layout: pipeline.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: texture.createView() },
      { binding: 1, resource: { buffer: curvesBuffer } },
    ],
  })

  const stagingBuffer = device.createBuffer({
    size: bytesPerRow * height,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ,
  })

  const encoder = device.createCommandEncoder()
  const pass = encoder.beginComputePass()
  pass.setPipeline(pipeline)
  pass.setBindGroup(0, bindGroup)
  pass.dispatchWorkgroups(
    Math.ceil(width / WORKING_GROUP_SIZE[0]),
    Math.ceil(height / WORKING_GROUP_SIZE[1])
  )
  pass.end()

  encoder.copyTextureToBuffer({ texture }, { buffer: stagingBuffer, bytesPerRow }, [width, height])
  device.queue.submit([encoder.finish()])

  await stagingBuffer.mapAsync(GPUMapMode.READ)
  const pixels = stagingBuffer.getMappedRange().slice(0)
  stagingBuffer.unmap()

  texture.destroy()
  curvesBuffer.destroy()
  stagingBuffer.destroy()

  ;(self as unknown as Worker).postMessage({ pixels, width, height, bytesPerRow, id }, [pixels])
  } catch (err) {
    console.error('[computeShape worker] compute failed:', err)
    throw err
  }
}
