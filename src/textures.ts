import { getLoadingTexture, getErrorTexture } from 'loadingTexture'
import { createTextureFromSource } from 'WebGPU/getTexture'
import { parse, RootNode, ElementNode } from 'svg-parser'
import addUiElement from 'svgToShapes/addUiElement'
import * as def from 'svgToShapes/definitions'
import type { Defs } from 'svgToShapes/definitions'
import RotateIcon from '../icons/rotate.svg'
import collectShapesData from 'svgToShapes/collectShapesData'
import { ZigAsset } from 'types'
import getShapesZigAssets from 'svgToShapes/getShapesZigAssets'
import { device, storageFormat } from 'WebGPU/device'

function getSvgSize(svgRoot: ElementNode, img?: HTMLImageElement) {
  const props = svgRoot.properties
  const viewboxSize = props?.viewBox ? extractSizeFromSvgViewbox(props.viewBox as string) : null

  const widthAttr = typeof props?.width === 'number' ? (props?.width as number) : undefined
  const heightAttr = typeof props?.height === 'number' ? (props?.height as number) : undefined
  const svgWidth = widthAttr || viewboxSize?.[0] || img?.naturalWidth
  const svgHeight = heightAttr || viewboxSize?.[1] || img?.naturalHeight
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

let textures: TextureSource[]
let textureLoadingPlaceholder: GPUTexture
let textureErrorPlaceholder: GPUTexture
let updateProcessing: () => void
let texturesLoading: number

export function init(_updateProcessing: (loadingTextures: number) => void): void {
  textures = []
  textureLoadingPlaceholder = getLoadingTexture()
  textureErrorPlaceholder = getErrorTexture()
  texturesLoading = 0
  updateProcessing = () => _updateProcessing(texturesLoading)

  addIcon(0, RotateIcon)
}

function addIcon(id: UiElementType, svg: string) {
  const svgTree = parse(svg)
  const svgRoot = svgTree.children[0] as ElementNode
  const [width, height] = getSvgSize(svgRoot)
  if (!width || !height) throw Error('SVG Icon width and height are required')
  const defs: Defs = {}
  def.collect(svgRoot, defs)
  def.resolveAll(defs)
  const shapesData = collectShapesData(svgRoot, defs)
  addUiElement(shapesData, id, height)
}

export interface TextureSource {
  url: string
  texture?: GPUTexture
  hash?: string
  data?: Uint8ClampedArray // it's time consuming to obtain data from a GPUTexture later
}

interface ImageExtractedData {
  width: number
  height: number
  isNewTexture?: boolean
  shapeAssets?: ZigAsset[]
  error?: unknown
}

export function add(url: string, onLoad?: (data: ImageExtractedData) => void): number {
  const sameUrl = textures.find((t) => t.url === url)
  if (sameUrl) {
    onLoad?.({
      width: sameUrl.texture!.width,
      height: sameUrl.texture!.height,
    })
    return textures.indexOf(sameUrl)
  }

  texturesLoading++
  updateProcessing()

  const textureId = textures.length
  // we allow duplicates in textures array
  textures.push({ url })
  resolveTexture(url, textureId, onLoad)

  return textureId
}

async function resolveTexture(
  url: string,
  textureId: number,
  onLoad?: (data: ImageExtractedData) => void
) {
  try {
    const [img, svgTree] = await Promise.all([getImage(url), getSvgRoot(url)])

    let existingTexture: TextureSource | null = null
    if (svgTree) {
      const svgRoot = svgTree.children[0] as ElementNode
      const [svgWidth, svgHeight] = getSvgSize(svgRoot, img)

      if (!svgWidth || !svgHeight) {
        throw Error('SVG width and height are required')
      }

      const defs: Defs = {}
      def.collect(svgRoot, defs)
      def.resolveAll(defs)
      const shapesData = collectShapesData(svgRoot, defs)

      onLoad?.({
        width: svgWidth,
        height: svgHeight,
        shapeAssets: getShapesZigAssets(shapesData, svgHeight),
      })
      return
    }

    const { ctx } = getImageData(img, img.naturalWidth, img.naturalHeight)
    const data = ctx.getImageData(0, 0, img.naturalWidth, img.naturalHeight).data
    const hash = hashImageData(data)

    existingTexture = findSameTexture(data, hash)
    if (existingTexture !== null) {
      textures[textureId] = existingTexture
    } else {
      textures[textureId].texture = createTextureFromSource(img, {
        flipY: true,
      })
      textures[textureId].data = data
      textures[textureId].hash = hash
    }

    onLoad?.({
      width: img.width,
      height: img.height,
      isNewTexture: !existingTexture,
    })
  } catch (error) {
    console.error(error)
    textures[textureId].texture = textureErrorPlaceholder
    onLoad?.({ error, width: 0, height: 0 })
    // onLoad has to be called, otherwise the Promise(waiting for onLoad)
    // will not resolve and the caller will keep waiting
  } finally {
    texturesLoading--
    updateProcessing()
  }
}

export function getTexture(textureId: number): GPUTexture {
  const texture = getOptionTexture(textureId)
  if (!texture) throw Error('Texture not found with id: ' + textureId)
  return texture
}

export function getTextureSafe(textureId: number): GPUTexture {
  return getOptionTexture(textureId) ?? textureLoadingPlaceholder
}

export function getOptionTexture(textureId: number): GPUTexture | undefined {
  return textures[textureId].texture
}

export function createCacheTexture(): number {
  const textureId = textures.length
  textures.push({ url: 'cache' })
  return textureId
}

export function createComputeDepthTexture(width: number, height: number): number {
  const textureId = textures.length
  const label = 'combineSdf - depth texture'
  const texture: GPUTexture = device.createTexture({
    label,
    size: [width, height],
    format: 'r32float',
    usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING,
  })

  textures.push({ url: label, texture })
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

export function emptySDF(textureId: number, width: number, height: number): void {
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

export function update(textureId: number, width: number, height: number): void {
  const existingTex = textures[textureId]?.texture

  if (!existingTex) throw Error('Texture not found with id: ' + textureId)

  if (existingTex.width === width && existingTex.height === height) {
    return
  }

  const texture: GPUTexture = device.createTexture({
    label: existingTex.label,
    size: [width, height],
    format: existingTex.format,
    usage: existingTex.usage,
  })

  existingTex?.destroy()
  textures[textureId].texture = texture
}

export function setCacheTexture(id: number, texture: GPUTexture) {
  if (textures[id].texture !== texture) {
    textures[id].texture?.destroy()
  }

  textures[id].texture = texture
}

export function getTextureCache(id: number, expectWidth: number, expectHeight: number): GPUTexture {
  const texture = textures[id].texture

  const canReuseTexture =
    texture &&
    Math.abs(texture.width - expectWidth) <= Number.EPSILON &&
    Math.abs(texture.height - expectHeight) <= Number.EPSILON

  if (!canReuseTexture) {
    texture?.destroy()
    const newTexture = device.createTexture({
      label: 'texture cache',
      format: storageFormat,
      usage:
        GPUTextureUsage.RENDER_ATTACHMENT |
        GPUTextureUsage.TEXTURE_BINDING |
        GPUTextureUsage.STORAGE_BINDING,
      size: [expectWidth, expectHeight],
    })
    textures[id].texture = newTexture
    return newTexture
  }

  return texture
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

function getImage(url: string): Promise<HTMLImageElement> {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.src = url
    img.onload = () => resolve(img)
    img.onerror = (err) => reject(err)
  })
}

async function getSvgRoot(url: string): Promise<RootNode | null> {
  const response = await fetch(url)
  const text = await response.text()
  if (text.includes('<svg')) {
    return parse(text)
  }
  return null
}
