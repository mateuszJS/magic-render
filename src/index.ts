import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import { createTextureFromSource } from 'WebGPU/getTexture'
import {
  init_state,
  add_asset,
  remove_asset,
  reset_assets,
  connect_on_asset_update_callback,
  connect_on_asset_selection_callback,
  destroy_state,
  import_icons,
} from './logic/index.zig'
import initMouseController from 'WebGPU/pointer'
import IconsPng from '../msdf/output/icons.png'
import IconsJson from '../msdf/output/icons.json'
import getDefaultPoints from 'utils/getDefaultPoints'

export type SerializedInputAsset = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  points?: PointUV[]
  url: string
  textureId?: number
}

export type SerializedOutputAsset = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  points: PointUV[]
  url: string
  textureId: number
}

export interface CreatorAPI {
  addImage: (url: string) => void
  resetAssets: (assets: SerializedInputAsset[], withSnapshot?: boolean) => void
  removeAsset: VoidFunction
  destroy: VoidFunction
}

export interface TextureSource {
  url: string
  texture?: GPUTexture
}

export default async function initCreator(
  canvas: HTMLCanvasElement,
  onAssetsUpdate: (assets: SerializedOutputAsset[]) => void,
  onAssetSelect: (assetId: number) => void,
  onProcessingUpdate: (inProgress: boolean) => void
): Promise<CreatorAPI> {
  let loadingTextures = 0
  let isMouseEventProcessing = false

  function updateProcessing() {
    onProcessingUpdate(loadingTextures > 0 || isMouseEventProcessing)
  }

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

  initMouseController(canvas, () => {
    isMouseEventProcessing = true
    updateProcessing()
  })

  const textures: TextureSource[] = []

  function addTexture(url: string, callback?: (width: number, height: number) => void): number {
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

  connect_on_asset_update_callback((serializedData: AssetZig[]) => {
    const serializedAssetsTextureUrl = [...serializedData].map<SerializedOutputAsset>((asset) => ({
      id: asset.id,
      textureId: asset.texture_id,
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

  connect_on_asset_selection_callback(onAssetSelect)

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = addTexture(url, (width, height) => {
      const points = getDefaultPoints(width, height, canvas.clientWidth, canvas.clientHeight)
      add_asset(0 /* no id yet, needs to be generated */, points, textureId)
    })
  }

  addTexture(IconsPng, (width, height) => {
    import_icons(
      IconsJson.chars.flatMap((char) => [
        char.id,
        char.x / width,
        char.y / height,
        char.width / width,
        char.height / height,
        char.width,
        char.height,
      ])
    )
  })

  const stopCreator = runCreator(canvas, context, device, presentationFormat, textures, () => {
    isMouseEventProcessing = false
    updateProcessing()
  })

  const resetAssets: CreatorAPI['resetAssets'] = async (assets, withSnapshot = false) => {
    const results = await Promise.allSettled(
      assets.map<Promise<AssetZig>>(
        (asset) =>
          new Promise((resolve, reject) => {
            if (asset.points) {
              return resolve({
                points: asset.points,
                texture_id: asset.textureId || addTexture(asset.url),
                id: asset.id || 0,
              })
            }

            const textureId = addTexture(asset.url, (width, height) => {
              // we wait to add iamge once poitns are known because otherwise
              // if we add img first with "Default" point value and update
              // it later ocne texture is loaded, we will get history snapshot with
              // that "default" points
              return resolve({
                points: getDefaultPoints(width, height, canvas.clientWidth, canvas.clientHeight),
                texture_id: textureId, // if there is no points, then for sure there is no asset.textureId
                id: 0,
              })
            })
          })
      )
    )

    const zigAssets = results
      .filter((result) => result.status === 'fulfilled')
      .map((result) => result.value)

    reset_assets(zigAssets, withSnapshot)
  }

  return {
    addImage,
    removeAsset: remove_asset,
    resetAssets,
    destroy: () => {
      stopCreator()
      destroy_state()
      context.unconfigure()
      device.destroy()
    },
  }
}
