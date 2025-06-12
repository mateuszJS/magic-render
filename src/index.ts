import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import { createTextureFromSource } from 'WebGPU/getTexture'
import {
  init_state,
  add_texture,
  connectOnAssetUpdateCallback,
  ASSET_ID_TRESHOLD,
} from './logic/index.zig'
import initMouseController from 'WebGPU/pointer'
import getDefaultPoints from 'utils/getDefaultPoints'

export type SerializedAsset = Omit<Texture, 'texture_id'> & {
  url: string
}

export interface CreatorAPI {
  addImage: (id: number, img: HTMLImageElement, points?: PointUV[]) => void
  destroy: VoidFunction
}

export interface TextureSource {
  url: string
  texture: GPUTexture
}

export default async function initCreator(
  canvas: HTMLCanvasElement,
  assets: SerializedAsset[],
  onAssetsUpdate: (assets: SerializedAsset[]) => void
): Promise<CreatorAPI> {
  /* setup WebGPU stuff */
  const device = await getDevice()

  init_state(canvas.clientWidth, canvas.clientHeight)
  const context = canvas.getContext('webgpu')
  if (!context) throw Error('WebGPU from canvas needs to be always provided')

  const presentationFormat = navigator.gpu.getPreferredCanvasFormat()
  context.configure({
    device,
    format: presentationFormat,
    // Specify we want both RENDER_ATTACHMENT and COPY_SRC since we
    // will copy out of the swapchain texture.
  })

  canvasSizeObserver(canvas, device, () => {
    // state.needsRefresh = true
  })

  initPrograms(device, presentationFormat)

  initMouseController(canvas)

  const textures: TextureSource[] = []
  runCreator(canvas, context, device, presentationFormat, textures)
  connectOnAssetUpdateCallback((serializedData: Texture[]) => {
    const serializedAssetsTextureUrl = [...serializedData].map<SerializedAsset>((asset) => ({
      id: asset.id,
      points: [...asset.points].map((point) => ({
        x: point.x,
        y: point.y,
        u: point.u,
        v: point.v,
      })),
      url: textures[asset.texture_id].url,
    }))
    onAssetsUpdate(serializedAssetsTextureUrl)
  })

  function addImage(id: number, img: HTMLImageElement, points?: PointUV[]) {
    if (id < ASSET_ID_TRESHOLD) {
      throw Error(`ID should be unique and not smaller than ${ASSET_ID_TRESHOLD}.`)
    }

    const newTextureId = textures.length
    textures.push({
      url: img.src,
      texture: createTextureFromSource(device, img, { flipY: true }),
    })

    add_texture(id, points || getDefaultPoints(img, canvas), newTextureId)
  }

  assets.forEach((asset) => {
    const img = new Image()
    img.src = asset.url
    img.onload = () => {
      addImage(asset.id, img, asset.points)
    }
  })

  return {
    addImage,
    destroy: () => {
      context.unconfigure()
      device.destroy()
    },
  }
}
