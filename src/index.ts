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

export type SerializedInputImage = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  points?: PointUV[]
  url: string
  textureId?: number
}

export type SerializedInputShape = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  paths: Point[][]
  props: ShapeProps
  bounds?: PointUV[]
  cache?: {
    id: number
    width: number
    height: number
    valid: boolean
  } | null
}

export type SerializedInputAsset = SerializedInputImage | SerializedInputShape

export type SerializedOutputImage = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  points: PointUV[]
  url: string
  textureId: number
}

export type SerializedOutputShape = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  paths: Point[][]
  props: ShapeProps
  bounds: PointUV[]
  cache: {
    id: number
    width: number
    height: number
    valid: boolean
  }
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

const NO_ASSET_ID = 0 // used when we don't have asset id yet

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

  let lastAssetsSnapshot: ZigAsset[] = []
  Logic.connectOnAssetUpdateCallback((serializedData: ZigAsset[]) => {
    lastAssetsSnapshot = [...serializedData]
    newAssetsSnapshot()
  })

  function newAssetsSnapshot() {
    // this function is not part of Logic.connect_on_asset_update_callback
    // only because once we update a texture url, we have to notify about the assets update
    const serializedAssetsTextureUrl = lastAssetsSnapshot.map<SerializedOutputAsset>((asset) => {
      if ('img' in asset && asset.img) {
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
      } else if ('shape' in asset && asset.shape) {
        const shape = asset.shape
        const cache = asset.shape.cache
        return {
          id: shape.id,
          paths: [...shape.paths].map((path) =>
            [...path].map((point) => ({
              x: point.x,
              y: point.y,
            }))
          ),
          bounds: [...shape.bounds].map((point) => ({
            x: point.x,
            y: point.y,
            u: point.u,
            v: point.v,
          })),
          props: {
            fill_color: [...shape.props.fill_color],
            stroke_color: [...shape.props.stroke_color],
            stroke_width: shape.props.stroke_width,
          },
          cache: {
            id: cache.id,
            width: cache.width,
            height: cache.height,
            valid: cache.valid,
          },
        }
      } else {
        throw Error('Unknown asset type')
      }
    })
    onAssetsUpdate(serializedAssetsTextureUrl)
  }

  Logic.connectOnAssetSelectionCallback(onAssetSelect)

  Logic.connectCacheCallbacks(
    Textures.createCacheTexture,
    startCache.bind(null, device, presentationFormat),
    endCache
  )

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, (width, height, isNew) => {
      const points = getDefaultPoints(width, height, projectWidth, projectHeight)
      Logic.addImage(0 /* no id yet, needs to be generated */, points, textureId)

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
      assets.map<Promise<ZigAsset>>(
        (asset) =>
          new Promise((resolve, reject) => {
            if ('paths' in asset) {
              // it's a shape
              console.log('asset', asset)
              return resolve({
                shape: {
                  id: asset.id || NO_ASSET_ID,
                  paths: asset.paths,
                  props: asset.props,
                  bounds: asset.bounds || [],
                  cache: {
                    id: asset.cache?.id || 0,
                    width: asset.cache?.width || 0,
                    height: asset.cache?.height || 0,
                    valid: asset.cache?.valid || false,
                  },
                },
              })
            } // otherwise it's an image

            if (asset.points) {
              return resolve({
                img: {
                  id: asset.id || NO_ASSET_ID,
                  points: asset.points, // here it makes sense
                  texture_id: asset.textureId || Textures.add(asset.url), // if we got points, so we have url on the server for sure
                },
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
                img: {
                  id: NO_ASSET_ID,
                  points: getDefaultPoints(width, height, projectWidth, projectHeight),
                  texture_id: textureId, // if there is no points, then for sure there is no asset.textureId
                },
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
