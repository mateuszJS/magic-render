import getLoadingTexture from 'loadingTexture'
import { parse, RootNode, Node, ElementNode } from 'svg-parser'
import { createTextureFromSource } from 'WebGPU/getTexture'
import * as Logic from 'logic/index.zig'
import parsePathData from 'parseSvg/parsePathData'
import parseRect from 'parseSvg/parseRect'
import type { PathSegment } from 'parseSvg/types'

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

function createShapes(node: Node, svgHeight: number): void {
  if (!('children' in node)) return

  node.children.forEach((child) => {
    if (typeof child !== 'string') {
      if ('properties' in child) {
        let result: PathSegment[][] | undefined = undefined

        switch (child.tagName) {
          case 'path':
            if (typeof child.properties?.d !== 'string') {
              throw Error("Path without 'd' property")
            }
            result = parsePathData(child.properties.d, svgHeight)
            break
          case 'rect':
            if (
              typeof child.properties?.width !== 'number' ||
              typeof child.properties?.height !== 'number'
            ) {
              throw Error("Path without 'd' property")
            }
            result = [parseRect(child.properties.width, child.properties.height, svgHeight)]
            break
        }

        if (result) {
          Logic.add_shape(result)
        }
      }
      createShapes(child, svgHeight)
    }
  })
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
      console.log(svgRoot)

      const svgHeight = svgRoot.properties?.height || img.naturalHeight
      if (!svgHeight || typeof svgHeight !== 'number') throw Error('SVG height is required')
      createShapes(svgRoot, svgHeight)
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
  return textures[textureId].texture ?? loadingTexture
}

export function setTexture(texture: GPUTexture, optionalId: number | null) {
  if (optionalId !== null) {
    textures[optionalId].texture?.destroy()
  }

  const id = optionalId ?? textures.length
  textures[id] = {
    url: 'cache',
    texture,
  }

  return id
}

export function getUrl(textureId: number): string {
  return textures[textureId].url
}

function getImageData(img: CanvasImageSource, width: number, height: number) {
  const canvas = document.createElement('canvas')!
  const ctx = canvas.getContext('2d')!
  canvas.width = width
  canvas.height = height
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
