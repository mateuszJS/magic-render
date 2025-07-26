import getLoadingTexture from 'loadingTexture'
import { createTextureFromSource } from 'WebGPU/getTexture'
import { init_svg_textures, add_svg_texture } from 'logic/index.zig'

let device: GPUDevice
let textures: TextureSource[]
let loadingTexture: GPUTexture
let updateProcessing: () => void
let loadingTextures: number

export function init(
  _device: GPUDevice,
  _updateProcessing: (loadingTextures: number) => void
): void {
  device = _device
  textures = []
  loadingTexture = getLoadingTexture(device)
  updateProcessing = () => _updateProcessing(loadingTextures)
  loadingTextures = 0
  init_svg_textures(device.limits.maxTextureDimension2D, increaseSize)
}

export interface TextureSource {
  url: string
  texture?: GPUTexture
  hash?: string
  data?: Uint8ClampedArray // it's time consuming to obtain data from a GPUTexture later
  svgImg?: HTMLImageElement // for SVG textures, we store the original image to redraw it with bigger size if needed
}

export function add(
  url: string,
  callback?: (width: number, height: number, isNew: boolean) => void
): number {
  loadingTextures++
  updateProcessing()

  const sameUrl = textures.find((t) => t.url === url)
  if (sameUrl) {
    loadingTextures--
    updateProcessing()
    callback?.(sameUrl.texture!.width, sameUrl.texture!.height, false)
    return textures.indexOf(sameUrl)
  }

  const textureId = textures.length
  // we allow duplicates in textures array
  textures.push({ url })

  getImageWithDetails(url).then(([img, { isSvg }]) => {
    const { ctx } = getImageData(
      img,
      img.naturalWidth,
      img.naturalHeight,
      img.naturalWidth,
      img.naturalHeight
    )
    const data = ctx.getImageData(0, 0, img.naturalWidth, img.naturalHeight).data
    const hash = hashImageData(data)

    const existingTexture = findSameTexture(data, hash)
    if (existingTexture !== null) {
      textures[textureId] = existingTexture
    } else {
      textures[textureId].texture = createTextureFromSource(device, img, { flipY: true })
      textures[textureId].data = data
      textures[textureId].hash = hash
      if (isSvg) {
        textures[textureId].svgImg = img
      }
    }

    if (isSvg) {
      add_svg_texture(textureId, img.naturalWidth, img.naturalHeight)
    }

    callback?.(img.width, img.height, !existingTexture)

    loadingTextures--
    updateProcessing()
  })

  return textureId
}

export function getTexture(textureId: number): GPUTexture {
  return textures[textureId].texture ?? loadingTexture
}

export function getUrl(textureId: number): string {
  return textures[textureId].url
}

function getImageData(
  img: CanvasImageSource,
  imgWidth: number,
  imgHeight: number,
  canvasWidth: number,
  canvasHeight: number
) {
  const canvas = document.createElement('canvas')!
  const ctx = canvas.getContext('2d')!
  canvas.width = canvasWidth
  canvas.height = canvasHeight
  ctx.drawImage(img, 0, 0, imgWidth, imgHeight, 0, 0, canvasWidth, canvasHeight)
  return { canvas, ctx }
}

/**
 * A simple, non-cryptographic hash function (djb2) for raw pixel data.
 * @param data The Uint8ClampedArray from getImageData.
 * @returns A hash string.
 */
function hashImageData(data: Uint8ClampedArray): string {
  let hash = 5381
  for (let i = 0; i < data.length; i++) {
    // Bitwise operations are fast
    hash = (hash << 5) + hash + data[i] /* hash * 33 + c */
  }
  return String(hash)
}

function findSameTexture(imgData: Uint8ClampedArray, hash: string): TextureSource | null {
  for (let i = 0; i < textures.length; i++) {
    const texture = textures[i]
    if (texture.hash === hash) {
      // if hashes match, perform more expensive data comparison
      // 2. If hashes match, perform the more expensive full pixel check
      if (imgData.length !== texture.data!.length) {
        return null
      }

      for (let i = 0; i < imgData.length; i++) {
        if (imgData[i] !== texture.data![i]) {
          return null
        }
      }
      return texture
    }
  }

  return null
}

export function updateTextureUrl(textureId: number, url: string) {
  textures[textureId].url = url
}

async function getImageWithDetails(url: string): Promise<[HTMLImageElement, { isSvg: boolean }]> {
  return Promise.all([
    new Promise<HTMLImageElement>((resolve) => {
      const img = new Image()
      img.src = url
      img.onload = () => resolve(img)
    }),
    new Promise<{ isSvg: boolean }>((resolve) => {
      fetch(url)
        .then((response) => response.blob())
        .then((blob) => {
          resolve({ isSvg: blob.type === 'image/svg+xml' })
        })
    }),
  ])
}

function increaseSize(textureId: number, width: number, height: number) {
  const img = textures[textureId].svgImg!
  const { canvas } = getImageData(img, img.naturalWidth, img.naturalHeight, width, height)
  console.log(width, height)
  textures[textureId].texture!.destroy()
  textures[textureId].texture = createTextureFromSource(device, canvas, {
    flipY: true,
  })
}
