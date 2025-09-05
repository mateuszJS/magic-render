import shaderCode from './index.wgsl'

const tileDim = 128
const batch = [4, 4]

export default function getProgram(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  const module = device.createShaderModule({
    label: 'blur shader module',
    code: shaderCode.replace('{presentationFormat}', presentationFormat),
  })

  const blurPipeline = device.createComputePipeline({
    layout: 'auto',
    compute: {
      module,
      entryPoint: 'main',
    },
  })

  const sampler = device.createSampler({
    magFilter: 'linear',
    minFilter: 'linear',
  })

  const buffer0 = (() => {
    const buffer = device.createBuffer({
      size: 4,
      mappedAtCreation: true,
      usage: GPUBufferUsage.UNIFORM,
    })
    new Uint32Array(buffer.getMappedRange())[0] = 0
    buffer.unmap()
    return buffer
  })()

  const buffer1 = (() => {
    const buffer = device.createBuffer({
      size: 4,
      mappedAtCreation: true,
      usage: GPUBufferUsage.UNIFORM,
    })
    new Uint32Array(buffer.getMappedRange())[0] = 1
    buffer.unmap()
    return buffer
  })()

  const blurParamsBufferX = device.createBuffer({
    size: 24,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.UNIFORM,
  })
  const blurParamsBufferY = device.createBuffer({
    size: 24,
    usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.UNIFORM,
  })

  return function renderBlur(
    encoder: GPUCommandEncoder,
    texture: GPUTexture,
    filterSizeX: number,
    filterSizeY: number,
    sigmaX: number,
    sigmaY: number,
    iterations: number
  ) {
    const textures = [
      device.createTexture({
        label: 'draw blur swap texture',
        size: {
          width: texture.width,
          height: texture.height,
        },
        format: texture.format,
        usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
      }),
      texture,
    ]

    const computeConstantsX = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: sampler },
        { binding: 1, resource: { buffer: blurParamsBufferX } },
        { binding: 2, resource: textures[1].createView() },
        { binding: 3, resource: textures[0].createView() },
        { binding: 4, resource: { buffer: buffer0 } },
      ],
    })
    const computeConstantsY = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: sampler },
        { binding: 1, resource: { buffer: blurParamsBufferY } },
        { binding: 2, resource: textures[0].createView() },
        { binding: 3, resource: textures[1].createView() },
        { binding: 4, resource: { buffer: buffer1 } },
      ],
    })

    const blockDimX = Math.max(1, tileDim - (filterSizeX - 1))
    const blockDimY = Math.max(1, tileDim - (filterSizeY - 1))

    const dataViewX = new DataView(new ArrayBuffer(5 * 4))
    dataViewX.setInt32(0, filterSizeX, true)
    dataViewX.setUint32(4, blockDimX, true)
    dataViewX.setFloat32(8, sigmaX, true)
    dataViewX.setFloat32(12, sigmaY, true)

    const dataViewY = new DataView(dataViewX.buffer.slice())
    dataViewY.setInt32(0, filterSizeY, true)
    dataViewY.setUint32(4, blockDimY, true)

    device.queue.writeBuffer(blurParamsBufferX, 0, dataViewX)
    device.queue.writeBuffer(blurParamsBufferY, 0, dataViewY)

    const computePass = encoder.beginComputePass({
      label: 'blur-pass',
    })
    computePass.setPipeline(blurPipeline)

    for (let i = 0; i < iterations; ++i) {
      // Horizontal pass (flip = 0): use X kernel
      computePass.setBindGroup(0, computeConstantsX)
      computePass.dispatchWorkgroups(
        Math.ceil(texture.width / blockDimX),
        Math.ceil(texture.height / batch[1])
      )
      // exchange width with height!
      // Vertical pass (flip = 1): use Y kernel
      computePass.setBindGroup(0, computeConstantsY)
      computePass.dispatchWorkgroups(
        Math.ceil(texture.height / blockDimY),
        Math.ceil(texture.width / batch[1])
      )
    }

    computePass.end()
  }
}
