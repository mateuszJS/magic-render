import createCheckedImageData from './createCheckedImageData'
import generateMipmapsArray from './generateMimapsArray'

interface Options {
  mips?: boolean
  flipY?: boolean
  depthOrArrayLayers?: number
}

type TextureSource =
  | ImageBitmap
  | HTMLVideoElement
  | HTMLCanvasElement
  | HTMLImageElement
  | OffscreenCanvas

const numMipLevels = (...sizes: number[]) => {
  const maxSize = Math.max(...sizes)
  return (1 + Math.log2(maxSize)) | 0
}

export interface TextureSlice {
  source: GPUCopyExternalImageSource
  fakeMipmaps: boolean
}

function createCheckedMipmap(levels: Array<{ size: number; color: string }>) {
  const ctx = new OffscreenCanvas(0, 0).getContext('2d', { willReadFrequently: true })!

  return levels.map(({ size, color }, i) => {
    ctx.canvas.width = size
    ctx.canvas.height = size
    ctx.fillStyle = i & 1 ? '#000' : '#fff'
    ctx.fillRect(0, 0, size, size)
    ctx.fillStyle = color
    ctx.fillRect(0, 0, size / 2, size / 2)
    ctx.fillRect(size / 2, size / 2, size / 2, size / 2)

    ctx.fillStyle = i & 1 ? '#FFFFFF' : '#000000'
    ctx.font = `${size * 0.3}px serif`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ;[
      { x: 0.25, y: 0.25 },
      { x: 0.25, y: 0.75 },
      { x: 0.75, y: 0.75 },
      { x: 0.75, y: 0.25 },
    ].forEach((p) => {
      ctx.fillText(i.toString(), p.x * size, p.y * size)
    })

    return ctx.getImageData(0, 0, size, size)
  })
}

export function createTextureArray(
  device: GPUDevice,
  width: number,
  height: number,
  slices: number
) {
  return device.createTexture({
    label: '2d array texture',
    format: 'rgba8unorm',
    mipLevelCount: 1 + Math.log2(2048),
    size: [width, height, slices],
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  })
}

// adds texture ot texture array
export function attachSlice(
  device: GPUDevice,
  textue2dArray: GPUTexture,
  width: number,
  height: number,
  source: GPUCopyExternalImageSource,
  sliceIndex: number,
  options: Options = {}
) {
  device.queue.copyExternalImageToTexture(
    { source },
    { texture: textue2dArray, origin: { z: sliceIndex }, mipLevel: 0 },
    { width, height }
  )

  // if (texSlice.fakeMipmaps) {
  //   let mipLevel = 1, size = width
  //   while ((size >>= 1) >= 1) {
  //     const { data, width, height} = createCheckedImageData(size, mipLevel)
  //     device.queue.writeTexture(
  //       { texture: textue2dArray, origin: { z: sliceIndex }, mipLevel },
  //       data,
  //       { bytesPerRow: width * 4 },
  //       { width, height },
  //     );
  //     mipLevel++
  //   }
  // } else {
  //   generateMipmapsArray(device, textue2dArray, {
  //     baseArrayLayer: sliceIndex,
  //     arrayLayerCount: 1,
  //   });
  // }
}

export function createTextureFromSource(
  device: GPUDevice,
  source: TextureSource,
  options: Options = {}
) {
  const texture = device.createTexture({
    format: 'rgba8unorm',
    mipLevelCount: options.mips ? numMipLevels(source.width, source.height) : 1,
    size: [source.width, source.height],
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  })
  copySourceToTexture(device, texture, source, options)
  return texture
}

function copySourceToTexture(
  device: GPUDevice,
  texture: GPUTexture,
  source: TextureSource,
  { flipY, depthOrArrayLayers }: Options = {}
) {
  device.queue.copyExternalImageToTexture(
    { source, flipY },
    {
      texture,
      // premultipliedAlpha: true
    },
    { width: source.width, height: source.height, depthOrArrayLayers }
  )

  // if (texture.mipLevelCount > 1) {
  //   generateMipmaps(device, texture);
  // }
}

export async function loadImageBitmap(url: string) {
  const res = await fetch(url)
  const blob = await res.blob()
  return await createImageBitmap(blob, {
    colorSpaceConversion: 'none',
    premultiplyAlpha: 'premultiply',
  })
}

export async function createTextureFromImage(device: GPUDevice, url: string, options: Options) {
  const imgBitmap = await loadImageBitmap(url)
  return createTextureFromSource(device, imgBitmap, options)
}
