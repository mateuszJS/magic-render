import { device, presentationFormat } from 'WebGPU/device'
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
  presentationFormat: GPUTextureFormat,
  width: number,
  height: number,
  slices: number
) {
  return device.createTexture({
    label: '2d array texture',
    format: presentationFormat,
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

/* instead of TextureSource the source accepts only ImageBitmap, it's important,
  e.g.HTMLImageElement has color profile attached to it (like Display P3 from iPhone screenshots)
  and Safari copies those values directly into sRGB texture, so colors looks funky.
  Instead we covnerted image to createImageBitmap with colorSpaceConversion "none"
  what strips the color profile and normalizes values to sRGB
*/
export function createTextureFromSource(source: ImageBitmap, options: Options = {}) {
  console.log('presentationFormat', presentationFormat)
  const texture = device.createTexture({
    label: 'createTextureFromSource',
    format: presentationFormat,
    mipLevelCount: options.mips ? numMipLevels(source.width, source.height) : 1,
    size: [source.width, source.height],
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  })
  copySourceToTexture(texture, source, options)
  return texture
}

function copySourceToTexture(
  texture: GPUTexture,
  source: TextureSource,
  { flipY, depthOrArrayLayers }: Options = {}
) {
  device.queue.copyExternalImageToTexture(
    { source, flipY },
    {
      texture,
      premultipliedAlpha: true,
    },
    { width: source.width, height: source.height, depthOrArrayLayers }
  )

  // if (texture.mipLevelCount > 1) {
  //   generateMipmaps(device, texture);
  // }
}
