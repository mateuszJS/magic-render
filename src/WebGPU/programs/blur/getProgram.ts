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

  return function renderBlur(encoder: GPUCommandEncoder, texture: GPUTexture) {
    const textures = [0, 1].map((_, index) => {
      if (index === 1) return texture

      return device.createTexture({
        label: `render blur index: ${index}`,
        size: {
          width: texture.width,
          height: texture.height,
        },
        format: texture.format,
        usage:
          GPUTextureUsage.COPY_DST |
          GPUTextureUsage.STORAGE_BINDING |
          GPUTextureUsage.TEXTURE_BINDING,
      })
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

    const blurParamsBuffer = device.createBuffer({
      size: 8,
      usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.UNIFORM,
    })

    const sampler = device.createSampler({
      magFilter: 'linear',
      minFilter: 'linear',
    })

    const computeConstants = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(0),
      entries: [
        {
          binding: 0,
          resource: sampler,
        },
        {
          binding: 1,
          resource: {
            buffer: blurParamsBuffer,
          },
        },
      ],
    })

    const computeBindGroup0 = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(1),
      entries: [
        {
          binding: 1,
          resource: textures[1].createView(),
          // resource: texture.createView(),
        },
        {
          binding: 2,
          resource: textures[0].createView(),
        },
        {
          binding: 3,
          resource: {
            buffer: buffer0,
          },
        },
      ],
    })

    const computeBindGroup1 = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(1),
      entries: [
        {
          binding: 1,
          resource: textures[0].createView(),
        },
        {
          binding: 2,
          resource: textures[1].createView(),
        },
        {
          binding: 3,
          resource: {
            buffer: buffer1,
          },
        },
      ],
    })

    const computeBindGroup2 = device.createBindGroup({
      layout: blurPipeline.getBindGroupLayout(1),
      entries: [
        {
          binding: 1,
          resource: textures[1].createView(),
        },
        {
          binding: 2,
          resource: textures[0].createView(),
        },
        {
          binding: 3,
          resource: {
            buffer: buffer0,
          },
        },
      ],
    })

    const settings = {
      filterSize: 15,
      iterations: 2,
    }

    // const blockDim = 128 - (15 - 1) = 114
    const blockDim = tileDim - (settings.filterSize - 1)
    device.queue.writeBuffer(blurParamsBuffer, 0, new Uint32Array([settings.filterSize, blockDim]))

    const computePass = encoder.beginComputePass({
      label: 'blur-pass',
    })
    computePass.setPipeline(blurPipeline)
    computePass.setBindGroup(0, computeConstants)

    computePass.setBindGroup(1, computeBindGroup0)
    computePass.dispatchWorkgroups(
      Math.ceil(texture.width / blockDim),
      Math.ceil(texture.height / batch[1])
    )

    computePass.setBindGroup(1, computeBindGroup1)
    computePass.dispatchWorkgroups(
      Math.ceil(texture.height / blockDim),
      Math.ceil(texture.width / batch[1])
    )

    for (let i = 0; i < settings.iterations - 1; ++i) {
      computePass.setBindGroup(1, computeBindGroup2)
      computePass.dispatchWorkgroups(
        Math.ceil(texture.width / blockDim), // 1200 / 114 = 11 ~ 10.52
        Math.ceil(texture.height / batch[1]) // 800 / 4 = 200
      )
      // exchange width with height!
      computePass.setBindGroup(1, computeBindGroup1)
      computePass.dispatchWorkgroups(
        Math.ceil(texture.height / blockDim),
        Math.ceil(texture.width / batch[1])
      )
    }

    computePass.end()

    // return textures[1]
  }
}
