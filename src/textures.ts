import getLoadingTexture from 'loadingTexture'
import { createTextureFromSource } from 'WebGPU/getTexture'

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
}

export interface TextureSource {
  url: string
  texture?: GPUTexture
}

export function add(url: string, callback?: (width: number, height: number) => void): number {
  loadingTextures++
  updateProcessing()

  const textureId = textures.length
  textures.push({ url })

  const img = new Image()
  img.src = url

  img.onload = () => {
    textures[textureId].texture = createTextureFromSource(device, img, { flipY: true })
    callback?.(img.width, img.height)

    loadingTextures--
    updateProcessing()
  }

  img.onerror = () => {
    console.error(`Failed to load image from ${url}`)

    loadingTextures--
    updateProcessing()
  }

  return textureId
}

export function getTexture(textureId: number): GPUTexture {
  return textures[textureId].texture ?? loadingTexture
}

export function getUrl(textureId: number): string {
  return textures[textureId].url
}
