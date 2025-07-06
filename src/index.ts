import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import { createTextureFromSource } from 'WebGPU/getTexture'
import {
  init_state,
  add_asset,
  remove_asset,
  connect_on_asset_update_callback,
  destroy_state,
  import_icons,
} from './logic/index.zig'
import initMouseController from 'WebGPU/pointer'
import getDefaultPoints from 'utils/getDefaultPoints'
import IconsPng from '../msdf/output/icons.png'
import IconsJson from '../msdf/output/icons.json'

export type SerializedAsset = Omit<AssetZig, 'texture_id'> & {
  url: string
}

export interface CreatorAPI {
  addImage: (img: HTMLImageElement, points?: PointUV[]) => void
  removeAsset: VoidFunction
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

  const textures: TextureSource[] = [{} as TextureSource /*reserved for icons texture*/]
  connect_on_asset_update_callback((serializedData: AssetZig[]) => {
    const serializedAssetsTextureUrl = [...serializedData].map<SerializedAsset>((asset) => ({
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

  function addImage(img: HTMLImageElement, points?: PointUV[]) {
    const newTextureId = textures.length
    textures.push({
      url: img.src,
      texture: createTextureFromSource(device, img, { flipY: true }),
    })

    add_asset(points || getDefaultPoints(img, canvas), newTextureId)
  }

  assets.forEach((asset) => {
    const img = new Image()
    img.src = asset.url
    img.onload = () => {
      addImage(img, asset.points)
    }
  })

  const icons = new Image()
  icons.src = IconsPng
  icons.onload = () => {
    textures[0].texture = createTextureFromSource(device, icons, { flipY: true })
    import_icons(
      IconsJson.chars.flatMap((char) => [
        char.id,
        char.x / icons.width,
        char.y / icons.height,
        char.width / icons.width,
        char.height / icons.height,
        char.width,
        char.height,
      ])
    )
  }

  const stopCreator = runCreator(canvas, context, device, presentationFormat, textures)

  function removeAsset() {
    remove_asset()
  }

  return {
    addImage,
    removeAsset,
    destroy: () => {
      stopCreator()
      destroy_state()
      context.unconfigure()
      device.destroy()
    },
  }
}
