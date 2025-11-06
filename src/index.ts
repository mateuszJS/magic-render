import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import * as Logic from './logic/index.zig'
import initMouseController, { camera } from 'pointer'
import getDefaultPoints from 'utils/getDefaultPoints'
import * as Textures from 'textures'
import throttle from 'utils/throttle'
import generatePreview from 'WebGPU/generatePreview'
import sanitizeFill from 'sanitizeFill'
import * as Typing from 'typing'
import * as Fonts from 'fonts'
import {
  CreatorTool,
  Id,
  PointUV,
  SerializedInputAsset,
  SerializedOutputAsset,
  ShapeProps,
  ZigAsset,
} from './types'
export * from './types'
import { destroyCanvasTextures } from 'getCanvasRenderDescriptor'

export interface CreatorAPI {
  addImage: (url: string) => void
  resetAssets: (assets: SerializedInputAsset[], withSnapshot?: boolean) => void
  removeAsset: VoidFunction
  destroy: VoidFunction
  setTool: (tool: CreatorTool) => void
  toggleSharedTextEffects: VoidFunction
  // we need to obtain live update!
  updateAssetProps: (props: Partial<ShapeProps>) => void // updates properties of selected asset
  updateAssetBounds: (bounds: PointUV[]) => void // updates bounds of selected asset
}

const NO_ASSET_ID = 0 // used when we don't have asset id yet

export default async function initCreator(
  canvas: HTMLCanvasElement,
  uploadTexture: (url: string, onNewUrl: (newUrl: string) => void) => void,
  onAssetsUpdate: (assets: SerializedOutputAsset[]) => void,
  onAssetSelect: (assetId: Id) => void,
  onIsProcessingFlagUpdate: (inProgress: boolean) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void,
  onUpdateTool: (tool: CreatorTool) => void,
  onUpdateProps: (bounds: PointUV[] | null, props: Partial<ShapeProps> | null) => void
  // called when properties/bounds of selected asset have been changed
  // including modifications caused by calling "updateAssetProps"
  // also called with null when no asset is selected
): Promise<CreatorAPI> {
  let texturesLoading = 0
  let isMouseEventProcessing = false

  function updateIsProcessingFlag() {
    onIsProcessingFlagUpdate(texturesLoading > 0 || isMouseEventProcessing)
  }
  let isDestroyed = false
  const { device, presentationFormat, storageFormat } = await getDevice()

  const projectWidth = canvas.clientWidth / 2
  const projectHeight = canvas.clientHeight / 2

  Logic.initState(
    projectWidth,
    projectHeight,
    device.limits.maxTextureDimension2D,
    device.limits.maxBufferSize
  )

  Textures.init(device, presentationFormat, storageFormat, (texLoadings) => {
    texturesLoading = texLoadings
    updateIsProcessingFlag()

    if (texturesLoading == 0) {
      triggerGeneratePreview()
    }
  })

  // rotation doesnt work
  const context = canvas.getContext('webgpu')
  if (!context) throw Error('WebGPU from canvas needs to be always provided')

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

  initPrograms(device, presentationFormat)

  initMouseController(canvas, updateRenderScale, () => {
    isMouseEventProcessing = true
    updateIsProcessingFlag()
  })

  const throttledPreviewGenerator = throttle(() => {
    if (isDestroyed || texturesLoading > 0) return

    generatePreview(
      device,
      presentationFormat,
      canvas,
      projectWidth,
      projectHeight,
      canvas.width / canvas.clientWidth, // it's pixels density
      // we have to use DOM-attached canvas to obtain pixel density,
      // otherwise clientWidth = 0
      capturePreview,
      onPreviewUpdate
    )
  }, 1000 * 5)

  const triggerGeneratePreview = () => {
    if (texturesLoading === 0) {
      throttledPreviewGenerator()
    }
  }

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
          texture_id: img.texture_id,
          bounds: serializeBounds([...img.bounds]),
          url: Textures.getUrl(img.texture_id),
        }
      } else if ('shape' in asset && asset.shape) {
        const shape = asset.shape
        if (!shape.bounds) {
          throw Error('Shape bounds are missing in asset with id: ' + shape.id)
        }
        return {
          id: shape.id,
          paths: [...shape.paths].map((path) =>
            [...path].map((point) => ({
              x: point.x,
              y: point.y,
            }))
          ),
          bounds: serializeBounds([...shape.bounds]),
          props: serializeShapeProps(shape.props),
          sdf_texture_id: shape.sdf_texture_id,
          cache_texture_id: shape.cache_texture_id,
        }
      } else if ('text' in asset && asset.text) {
        return {
          id: asset.text.id,
          content: asset.text.content ?? '',
          bounds: serializeBounds([...asset.text.bounds]),
          font_size: asset.text.font_size,
          props: serializeShapeProps(asset.text.props),
        }
      } else {
        throw Error('Unknown asset type')
      }
    })
    onAssetsUpdate(serializedAssetsTextureUrl)
    triggerGeneratePreview()
  }

  Fonts.loadFont()

  Logic.connectOnAssetSelectionCallback((id) => onAssetSelect([...id] as Id))
  Logic.connectCreateSdfTexture(Textures.createSDF, Textures.createComputeDepthTexture)
  Logic.connectTyping(
    Typing.enable,
    Typing.disable,
    Typing.updateContent,
    Typing.updateSelection,
    Fonts.getCharData,
    Fonts.getKerning
  )
  Logic.onUpdateToolCallback(onUpdateTool)
  Logic.connectSelectedAssetUpdates((bounds, props) => {
    onUpdateProps(
      bounds && serializeBounds([...bounds]), //
      props && serializeShapeProps(props)
    )
  })

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, (width, height, isNew) => {
      const points = getDefaultPoints(width, height, projectWidth, projectHeight)
      Logic.addImage(NO_ASSET_ID /* no id yet, needs to be generated */, points, textureId)

      if (isNew) {
        uploadTexture(url, (newUrl) => {
          Textures.updateTextureUrl(textureId, newUrl)
          newAssetsSnapshot()
        })
      }
    })
  }

  const { stopRAF, capturePreview } = runCreator(canvas, context, device, () => {
    isMouseEventProcessing = false
    updateIsProcessingFlag()
  })

  const resetAssets: CreatorAPI['resetAssets'] = async (assets, withSnapshot = false) => {
    const results = await Promise.allSettled(
      assets.map<Promise<ZigAsset>>(
        (asset) =>
          new Promise((resolve) => {
            if ('paths' in asset) {
              // it's a shape
              return resolve({
                shape: {
                  id: asset.id || NO_ASSET_ID,
                  paths: asset.paths,
                  props: asset.props,
                  bounds: asset.bounds,
                  sdf_texture_id: asset.sdf_texture_id || Textures.createSDF(),
                  cache_texture_id: asset.cache_texture_id || null,
                },
              })
            } else if ('content' in asset) {
              return resolve({
                text: {
                  id: asset.id || NO_ASSET_ID,
                  content: asset.content,
                  bounds: asset.bounds,
                  font_size: asset.font_size,
                  props: asset.props,
                },
              })
            }
            // otherwise it's an image

            if (asset.bounds) {
              return resolve({
                img: {
                  id: asset.id || NO_ASSET_ID,
                  bounds: asset.bounds,
                  texture_id: asset.texture_id || Textures.add(asset.url), // if we got points, so we have url on the server for sure
                },
              })
            }

            const textureId = Textures.add(asset.url, (width, height, isNew) => {
              // we wait to add image once points are known. The other option was to add image first
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
                  bounds: getDefaultPoints(width, height, projectWidth, projectHeight), // TODO: do it in zig only liek for shaoes
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
    triggerGeneratePreview()
  }

  return {
    addImage,
    removeAsset: Logic.removeAsset,
    resetAssets,
    destroy: () => {
      isDestroyed = true
      stopRAF()
      Logic.deinitState()
      context.unconfigure()
      destroyCanvasTextures()
      device.destroy()
    },
    setTool: (tool) => {
      onUpdateTool(tool)
      Logic.setTool(tool)
    },
    toggleSharedTextEffects: Logic.toggleSharedTextEffects,
    updateAssetProps: (props) => {
      Logic.setSelectedAssetProps(props)
    },
    updateAssetBounds: (bounds) => {
      Logic.setSelectedAssetBounds(bounds)
    },
  }
}

function serializeBounds(bounds: PointUV[]): PointUV[] {
  return bounds.map((point) => ({
    x: point.x,
    y: point.y,
    u: point.u,
    v: point.v,
  }))
}

function serializeShapeProps(props: ShapeProps): ShapeProps {
  return {
    sdf_effects: [...props.sdf_effects].map((effect) => ({
      dist_start: effect.dist_start,
      dist_end: effect.dist_end,
      fill: sanitizeFill(effect.fill),
    })),
    filter: props.filter?.gaussianBlur
      ? {
          gaussianBlur: {
            x: props.filter.gaussianBlur.x,
            y: props.filter.gaussianBlur.y,
          },
        }
      : null,
    opacity: props.opacity,
  }
}
