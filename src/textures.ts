import getLoadingTexture from 'loadingTexture'
import { createTextureFromSource } from 'WebGPU/getTexture'
import { parse, RootNode, ElementNode } from 'svg-parser'
import { createShapes, collectDefs, Defs } from 'shapes/createShape'

function getSvgSize(svgRoot: ElementNode, img: HTMLImageElement) {
  const props = svgRoot.properties
  const viewboxSize = props?.viewBox ? extractSizeFromSvgViewbox(props.viewBox as string) : null

  const widthAttr = typeof props?.width === 'number' ? (props?.width as number) : undefined
  const heightAttr = typeof props?.height === 'number' ? (props?.height as number) : undefined
  const svgWidth = widthAttr || img.naturalWidth || viewboxSize?.[0]
  const svgHeight = heightAttr || img.naturalHeight || viewboxSize?.[1]
  return [svgWidth, svgHeight]
}

function extractSizeFromSvgViewbox(viewbox: string) {
  const parts = viewbox.split(' ').map(Number)
  if (parts.length === 4) {
    const [minX, minY, width, height] = parts
    return [width - minX, height - minY]
  }
  return null
}

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
  hash?: string
  data?: Uint8ClampedArray // it's time consuming to obtain data from a GPUTexture later
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

  getImageWithDetails(url).then(([img, svgTree]) => {
    if (svgTree) {
      const svgRoot = svgTree.children[0] as ElementNode
      const [svgWidth, svgHeight] = getSvgSize(svgRoot, img)
      if (!svgWidth || !svgHeight) throw Error('SVG width and height are required')
      const defs: Defs = {}
      collectDefs(svgRoot, defs)
      createShapes(svgRoot, defs, svgWidth, svgHeight)
      return
    }
    const { ctx } = getImageData(img, img.naturalWidth, img.naturalHeight)
    const data = ctx.getImageData(0, 0, img.naturalWidth, img.naturalHeight).data
    const hash = hashImageData(data)

    const existingTexture = findSameTexture(data, hash)
    if (existingTexture !== null) {
      textures[textureId] = existingTexture
    } else {
      textures[textureId].texture = createTextureFromSource(device, img, { flipY: true })
      textures[textureId].data = data
      textures[textureId].hash = hash
    }

    callback?.(img.width, img.height, !existingTexture)

    loadingTextures--
    updateProcessing()
  })

  return textureId
}

export function getTexture(textureId: number): GPUTexture {
  const texture = getOptionTexture(textureId)
  if (!texture) throw Error('Texture not found with id: ' + textureId)
  return texture
}

export function getTextureSafe(textureId: number): GPUTexture {
  return getOptionTexture(textureId) ?? loadingTexture
}

export function getOptionTexture(textureId: number): GPUTexture | undefined {
  return textures[textureId].texture
}

export function createCacheTexture(): number {
  const textureId = textures.length
  textures.push({ url: 'cache' })
  return textureId
}

export function createSDF(): number {
  const textureId = textures.length
  const label = `SDF texture ${textureId}`
  const texture: GPUTexture = device.createTexture({
    label,
    size: [1, 1],
    format: 'rgba32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })

  textures.push({ url: label, texture })
  return textureId
}

export function updateSDF(textureId: number, width: number, height: number): void {
  const label = `SDF texture ${textureId}`
  const texture: GPUTexture = device.createTexture({
    label,
    size: [width, height],
    format: 'rgba32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })

  textures[textureId].texture?.destroy()
  textures[textureId].texture = texture
}

export function setCacheTexture(id: number, texture: GPUTexture) {
  if (textures[id].texture !== texture) {
    textures[id].texture?.destroy()
  }

  textures[id].texture = texture
}

export function getUrl(textureId: number): string {
  return textures[textureId].url
}

function getImageData(img: CanvasImageSource, width: number, height: number) {
  const canvas = new OffscreenCanvas(width, height)
  const ctx = canvas.getContext('2d')!
  ctx.drawImage(img, 0, 0, width, height)
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
      // if hashes match, perform the more expensive full pixel check
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

async function getImageWithDetails(url: string): Promise<[HTMLImageElement, RootNode | null]> {
  return Promise.all([
    new Promise<HTMLImageElement>((resolve) => {
      const img = new Image()
      img.src = url
      img.onload = () => resolve(img)
    }),
    new Promise<RootNode | null>((resolve) => {
      fetch(url)
        .then((response) => response.text())
        .then((text) => {
          if (text.includes('<svg')) {
            resolve(parse(text))
          } else {
            resolve(null)
          }
        })
    }),
  ])
}
