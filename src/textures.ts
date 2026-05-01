import { getLoadingTexture, getErrorTexture } from 'placeholderTexture'
import { createTextureFromSource } from 'WebGPU/getTexture'
import { parse, RootNode, ElementNode } from 'svg-parser'
import addUiElement from 'svgToShapes/addUiElement'
import * as def from 'svgToShapes/definitions'
import type { Defs } from 'svgToShapes/definitions'
import RotateIcon from '../icons/rotate.svg'
import collectShapesData from 'svgToShapes/collectShapesData'
import { Asset } from 'types'
import getShapesAssets from 'svgToShapes/getShapesAssets'
import { device, storageFormat } from 'WebGPU/setupDevice'
import { delayedDestroy, destroyGpuObjects } from 'WebGPU/programs/initPrograms'
import * as PreviewTrigger from './previewTrigger'

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

export function init(): void {
  textures = []
  textureLoadingPlaceholder = getLoadingTexture()
  textureErrorPlaceholder = getErrorTexture()

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
}

interface ImageExtractedData {
  width: number
  height: number
  shapeAssets?: Asset[]
  error?: unknown
}

export function add(
  url: string,
  captureError: (error: unknown) => void,
  onLoad?: (data: ImageExtractedData) => void
): number {
  const sameUrl = textures.find((t) => t.url === url)
  if (sameUrl) {
    onLoad?.({
      width: sameUrl.texture!.width,
      height: sameUrl.texture!.height,
    })
    return textures.indexOf(sameUrl)
  }

  PreviewTrigger.updateResourcesFlag('texture-load-start')

  const textureId = textures.length
  // we allow duplicates in textures array
  textures.push({ url })
  resolveTexture(url, textureId, captureError, onLoad)

  return textureId
}

async function resolveTexture(
  url: string,
  textureId: number,
  captureError: (error: unknown) => void,
  onLoad?: (data: ImageExtractedData) => void
) {
  try {
    const [img, svgTree] = await Promise.all([getImage(url), getSvgRoot(url)])

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
        shapeAssets: getShapesAssets(shapesData, svgHeight),
      })
      return
    }

    // colorSpaceConversion: 'none' strips the embedded color profile (e.g. Display P3 from iPhone
    // screenshots) and treats values as sRGB. Without this, Safari copies P3 values verbatim into
    // an sRGB texture, producing oversaturated colors — while Chrome silently converts correctly.
    const bitmap = await createImageBitmap(img, { colorSpaceConversion: 'none' })

    textures[textureId].texture = createTextureFromSource(bitmap, {
      flipY: true,
    })

    bitmap.close()

    onLoad?.({
      width: img.width,
      height: img.height,
    })
  } catch (error) {
    captureError(error)
    textures[textureId].texture = textureErrorPlaceholder
    onLoad?.({ error, width: 0, height: 0 })
    // onLoad has to be called, otherwise the Promise(waiting for onLoad)
    // will not resolve and the caller will keep waiting
  } finally {
    PreviewTrigger.updateResourcesFlag('texture-load-end')
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

export function createDisposableComputeDepthTexture(width: number, height: number): number {
  const textureId = textures.length
  const label = 'combineSdf - depth texture'
  const texture: GPUTexture = device.createTexture({
    label,
    size: [width, height],
    format: 'depth24plus',
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
  })

  textures.push({ url: label, texture })

  delayedDestroy(texture)
  // TODO: also remove the entry from textures map

  return textureId
}

export function createSDF(): number {
  const textureId = textures.length
  const label = `SDF texture ${textureId}`
  const texture: GPUTexture = device.createTexture({
    label,
    size: [1, 1],
    format: 'r32float',
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
  })

  textures.push({ url: label, texture })
  return textureId
}

export function emptySDF(textureId: number, width: number, height: number): void {
  const label = `SDF texture ${textureId}`
  const texture: GPUTexture = device.createTexture({
    label,
    size: [width, height],
    format: 'r32float',
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
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
