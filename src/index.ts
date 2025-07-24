import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import {
  init_state,
  add_asset,
  remove_asset,
  reset_assets,
  connect_on_asset_update_callback,
  connect_on_asset_selection_callback,
  destroy_state,
  import_icons,
  update_render_scale,
} from './logic/index.zig'
import initMouseController, { camera } from 'WebGPU/pointer'
import IconsPng from '../msdf/output/icons.png'
import IconsJson from '../msdf/output/icons.json'
import getDefaultPoints from 'utils/getDefaultPoints'
import * as Textures from 'textures'

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

export default async function initCreator(
  canvas: HTMLCanvasElement,
  uploadTexture: (url: string, onNewUrl: (newUrl: string) => void) => void,
  onAssetsUpdate: (assets: SerializedOutputAsset[]) => void,
  onAssetSelect: (assetId: number) => void,
  onProcessingUpdate: (inProgress: boolean) => void
): Promise<CreatorAPI> {
  let loadingTextures = 0
  let isMouseEventProcessing = false

  function updateProcessing() {
    onProcessingUpdate(loadingTextures > 0 || isMouseEventProcessing)
  }

  const device = await getDevice()
  Textures.init(device, (texLoadings) => {
    loadingTextures = texLoadings
    updateProcessing()
  })

  const projectWidth = canvas.clientWidth / 2
  const projectHeight = canvas.clientHeight / 2

  init_state(projectWidth, projectHeight)
  // rotation doesnt work
  const context = canvas.getContext('webgpu')
  if (!context) throw Error('WebGPU from canvas needs to be always provided')

  const presentationFormat = navigator.gpu.getPreferredCanvasFormat()
  context.configure({
    device,
    format: presentationFormat,
    // Specify we want both RENDER_ATTACHMENT and COPY_SRC since we
    // will copy out of the swapchain texture.
  })

  function updateRenderScale() {
    update_render_scale(canvas.width / (canvas.clientWidth * camera.zoom))
  }

  let wasInitialOffsetSet = false
  canvasSizeObserver(canvas, device, () => {
    if (wasInitialOffsetSet === false) {
      camera.x = (canvas.width - projectWidth) / 2
      camera.y = (canvas.height - projectHeight) / 2
      wasInitialOffsetSet = true
    }
    updateRenderScale()
  })

  initPrograms(device, presentationFormat)

  initMouseController(canvas, updateRenderScale, () => {
    isMouseEventProcessing = true
    updateProcessing()
  })

  connect_on_asset_update_callback((serializedData: ZigAssetOutput[]) => {
    const serializedAssetsTextureUrl = [...serializedData].map<SerializedOutputAsset>((asset) => ({
      id: asset.id,
      textureId: asset.texture_id,
      points: [...asset.points].map((point) => ({
        x: point.x,
        y: point.y,
        u: point.u,
        v: point.v,
      })),
      url: Textures.getUrl(asset.texture_id),
    }))
    onAssetsUpdate(serializedAssetsTextureUrl)
  })

  connect_on_asset_selection_callback(onAssetSelect)

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, (width, height, isNew) => {
      const points = getDefaultPoints(width, height, projectWidth, projectHeight)
      add_asset(0 /* no id yet, needs to be generated */, points, textureId)

      if (isNew) {
        uploadTexture(url, (newUrl) => {
          Textures.updateTextureUrl(textureId, newUrl)
        })
      }
    })
  }

  Textures.add(IconsPng, (width, height) => {
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

  const stopCreator = runCreator(canvas, context, device, presentationFormat, () => {
    isMouseEventProcessing = false
    updateProcessing()
  })

  const resetAssets: CreatorAPI['resetAssets'] = async (assets, withSnapshot = false) => {
    const results = await Promise.allSettled(
      assets.map<Promise<ZigAssetInput>>(
        (asset) =>
          new Promise((resolve, reject) => {
            if (asset.points) {
              return resolve({
                points: asset.points, // here it makes sense
                texture_id: asset.textureId || Textures.add(asset.url), // if we got points, so we have url on the server for sure
                id: asset.id || 0,
              })
            }

            const textureId = Textures.add(asset.url, (width, height, isNew) => {
              // we wait to add image once points are known. Other option was to add image first
              // with "default" points and then update it once texture is loaded.
              // However, that would cause issues with undo/redo since we would have history
              // snapshot with "default" points and then update it to the real points.
              if (isNew) {
                uploadTexture(asset.url, (newUrl) => {
                  console.log(asset.url, newUrl)
                  Textures.updateTextureUrl(textureId, newUrl)
                })
              }

              return resolve({
                points: getDefaultPoints(width, height, projectWidth, projectHeight),
                texture_id: textureId, // if there is no points, then for sure there is no asset.textureId
                id: 0,
              })
            })
          })
      )
    )

    const serializedAssets = results
      .filter((result) => result.status === 'fulfilled')
      .map((result) => result.value)

    reset_assets(serializedAssets, withSnapshot)
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
