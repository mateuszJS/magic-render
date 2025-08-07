import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import * as Logic from './logic/index.zig'
import initMouseController, { camera } from 'WebGPU/pointer'
import IconsPng from '../msdf/output/icons.png'
import IconsJson from '../msdf/output/icons.json'
import getDefaultPoints from 'utils/getDefaultPoints'
import * as Textures from 'textures'
import { startCache, endCache } from 'WebGPU/textureCache'
import debounce from 'utils/debounce'
import generatePreview from 'WebGPU/generatePreview'

export type SerializedInputAsset = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  points?: PointUV[]
  url: string
  textureId?: number
}

export type SerializedOutputImage = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  points: PointUV[]
  url: string
  textureId: number
}

export type SerializedOutputShape = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  points: PointUV[]
  url: string
  textureId: number
  paths: Point[][]
}

export type SerializedOutputAsset = SerializedOutputImage | SerializedOutputShape

export enum CreatorTool {
  None = 0,
  DrawShape = 1,
}

export interface CreatorAPI {
  addImage: (url: string) => void
  resetAssets: (assets: SerializedInputAsset[], withSnapshot?: boolean) => void
  removeAsset: VoidFunction
  destroy: VoidFunction
  setTool: (tool: CreatorTool) => void
}

export default async function initCreator(
  canvas: HTMLCanvasElement,
  uploadTexture: (url: string, onNewUrl: (newUrl: string) => void) => void,
  onAssetsUpdate: (assets: SerializedOutputAsset[]) => void,
  onAssetSelect: (assetId: number) => void,
  onProcessingUpdate: (inProgress: boolean) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void
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

  Logic.initState(projectWidth, projectHeight, device.limits.maxTextureDimension2D)
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
    Logic.updateRenderScale(canvas.width / (canvas.clientWidth * camera.zoom))
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

  const cleanupPrograms = initPrograms(device, presentationFormat)

  initMouseController(canvas, updateRenderScale, () => {
    isMouseEventProcessing = true
    updateProcessing()
  })

  const triggerGeneratePreview = debounce(() => {
    generatePreview(
      device,
      presentationFormat,
      canvas,
      projectWidth,
      projectHeight,
      capturePreview,
      onPreviewUpdate
    )
  }, 1000 * 5)

  let lastAssetsSnapshot: ZigAssetOutput[] = []
  Logic.connectOnAssetUpdateCallback((serializedData: ZigAssetOutput[]) => {
    console.log([...serializedData])
    lastAssetsSnapshot = [...serializedData]
    newAssetsSnapshot()
  })

  function newAssetsSnapshot() {
    // this function is not part of Logic.connect_on_asset_update_callback
    // only because once we update a texture url, we have to notify about the assets update
    const serializedAssetsTextureUrl = lastAssetsSnapshot.map<SerializedOutputAsset>((asset) => {
      if (asset.img) {
        const img = asset.img
        return {
          id: img.id,
          textureId: img.texture_id,
          points: [...img.points].map((point) => ({
            x: point.x,
            y: point.y,
            u: point.u,
            v: point.v,
          })),
          url: Textures.getUrl(img.texture_id),
        }
      } else {
        const shape = asset.shape
        return {
          id: shape.id,
          textureId: shape.texture_id,
          points: [...shape.points].map((point) => ({
            x: point.x,
            y: point.y,
            u: point.u,
            v: point.v,
          })),
          url: Textures.getUrl(shape.texture_id),
          paths: [...shape.paths].map((path) =>
            [...path].map((point) => ({
              x: point.x,
              y: point.y,
            }))
          ),
        }
      }
    })
    onAssetsUpdate(serializedAssetsTextureUrl)
  }

  Logic.connectOnAssetSelectionCallback(onAssetSelect)

  Logic.connectCacheCallbacks((textureId, boundingBox, width, height) => {
    return startCache(device, presentationFormat, textureId, boundingBox, width, height)
  }, endCache)

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, (width, height, isNew) => {
      const points = getDefaultPoints(width, height, projectWidth, projectHeight)
      Logic.addAsset(0 /* no id yet, needs to be generated */, points, textureId)

      if (isNew) {
        uploadTexture(url, (newUrl) => {
          Textures.updateTextureUrl(textureId, newUrl)
          triggerGeneratePreview() // we do it in the callback because new texture might be not loaded yet from blob
          newAssetsSnapshot()
        })
      }
    })
  }

  Textures.add(IconsPng, (width, height) => {
    Logic.importIcons(
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

  const { stopRAF, capturePreview } = runCreator(
    canvas,
    context,
    device,
    cleanupPrograms,
    presentationFormat,
    () => {
      isMouseEventProcessing = false
      updateProcessing()
    }
  )

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
                  Textures.updateTextureUrl(textureId, newUrl)
                  newAssetsSnapshot()
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

    Logic.resetAssets(serializedAssets, withSnapshot)
  }

  return {
    addImage,
    removeAsset: Logic.removeAsset,
    resetAssets,
    destroy: () => {
      stopRAF()
      Logic.destroyState()
      context.unconfigure()
      device.destroy()
    },
    setTool: Logic.setTool,
  }
}
