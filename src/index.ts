import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import * as Logic from './logic/index.zig'
import initMouseController, { camera } from 'pointer'
import getDefaultPoints from 'utils/getDefaultPoints'
import * as Textures from 'textures'
import debounce from 'utils/debounce'
import generatePreview from 'WebGPU/generatePreview'
import sanitizeFill from 'sanitizeFill'
import * as Typing from 'typing'
import * as Fonts from 'fonts'

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
  sdf_texture_id?: number
  cache_texture_id?: number | null
  bounds?: PointUV[]
}

export type SerializedInputText = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  content: string
  bounds?: PointUV[]
  max_width: number
  font_size: number
}

export type SerializedInputAsset = SerializedInputImage | SerializedInputShape | SerializedInputText

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
  sdf_texture_id: number
  cache_texture_id: number | null
}

export type SerializedOutputText = {
  id: number // not needed while loading project but useful for undo/redo to maintain selection
  content: string
  bounds: PointUV[]
  max_width: number
  font_size: number
}

export type SerializedOutputAsset =
  | SerializedOutputImage
  | SerializedOutputShape
  | SerializedOutputText

export enum CreatorTool {
  None = 0,
  DrawShape = 1,
  EditShape = 2,
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
  onAssetSelect: (assetId: Id) => void,
  onProcessingUpdate: (inProgress: boolean) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void
): Promise<CreatorAPI> {
  let loadingTextures = 0
  let isMouseEventProcessing = false

  function updateProcessing() {
    onProcessingUpdate(loadingTextures > 0 || isMouseEventProcessing)
  }

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
    loadingTextures = texLoadings
    updateProcessing()
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
    updateProcessing()
  })

  const triggerGeneratePreview = debounce(() => {
    generatePreview(
      device,
      presentationFormat,
      canvas,
      projectWidth,
      projectHeight,
      canvas.width / canvas.clientWidth, // only impacted by pixels density
      // because of that we can use our normal canvas as well
      // we dont use new canvas(created inside generatePreview), because it's not added to DOM
      // so clientWidth = 0
      capturePreview,
      onPreviewUpdate
    )
  }, 1000 * 5)

  let lastAssetsSnapshot: ZigAssetOutput[] = []
  Logic.connectOnAssetUpdateCallback((serializedData: ZigAssetOutput[]) => {
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
            sdf_effects: [...shape.props.sdf_effects].map((effect) => ({
              dist_start: effect.dist_start,
              dist_end: effect.dist_end,
              fill: sanitizeFill(effect.fill),
            })),
            filter: shape.props.filter?.gaussianBlur
              ? {
                  gaussianBlur: {
                    x: shape.props.filter.gaussianBlur.x,
                    y: shape.props.filter.gaussianBlur.y,
                  },
                }
              : null,
            opacity: shape.props.opacity,
          },
          sdf_texture_id: shape.sdf_texture_id,
          cache_texture_id: shape.cache_texture_id,
        }
      } else if ('text' in asset && asset.text) {
        return {
          id: asset.text.id,
          content: asset.text.content,
          bounds: [...asset.text.bounds].map((point) => ({
            x: point.x,
            y: point.y,
            u: point.u,
            v: point.v,
          })),
          max_width: asset.text.max_width,
          font_size: asset.text.font_size,
        }
      } else {
        throw Error('Unknown asset type')
      }
    })
    onAssetsUpdate(serializedAssetsTextureUrl)
  }

  Fonts.loadFont()

  Logic.connectOnAssetSelectionCallback(onAssetSelect)
  Logic.connectCreateSdfTexture(Textures.createSDF)
  Logic.connectTyping(
    Typing.enable,
    Typing.disable,
    Typing.update,
    Fonts.getCharData,
    Fonts.getKerning
  )

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, (width, height, isNew) => {
      const points = getDefaultPoints(width, height, projectWidth, projectHeight)
      Logic.addImage(NO_ASSET_ID /* no id yet, needs to be generated */, points, textureId)

      if (isNew) {
        uploadTexture(url, (newUrl) => {
          Textures.updateTextureUrl(textureId, newUrl)
          triggerGeneratePreview() // we do it in the callback because new texture might be not loaded yet from blob
          newAssetsSnapshot()
        })
      }
    })
  }

  const { stopRAF, capturePreview } = runCreator(canvas, context, device, () => {
    isMouseEventProcessing = false
    updateProcessing()
  })

  const resetAssets: CreatorAPI['resetAssets'] = async (assets, withSnapshot = false) => {
    const results = await Promise.allSettled(
      assets.map<Promise<ZigAssetInput>>(
        (asset) =>
          new Promise((resolve, reject) => {
            if ('paths' in asset) {
              // it's a shape
              return resolve({
                shape: {
                  id: asset.id || NO_ASSET_ID,
                  paths: asset.paths,
                  props: asset.props,
                  bounds: asset.bounds || null,
                  sdf_texture_id: asset.sdf_texture_id || Textures.createSDF(),
                  cache_texture_id: asset.cache_texture_id || null,
                },
              })
            } else if ('content' in asset) {
              return resolve({
                text: {
                  id: asset.id || NO_ASSET_ID,
                  content: asset.content,
                  bounds: asset.bounds || null,
                  max_width: asset.max_width,
                  font_size: asset.font_size,
                },
              })
            }
            // otherwise it's an image

            if (asset.points) {
              return resolve({
                img: {
                  id: asset.id || NO_ASSET_ID,
                  points: asset.points,
                  texture_id: asset.textureId || Textures.add(asset.url), // if we got points, so we have url on the server for sure
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
                  points: getDefaultPoints(width, height, projectWidth, projectHeight), // TODO: do it in zig only liek for shaoes
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
      Logic.deinitState()
      context.unconfigure()
      device.destroy()
    },
    setTool: Logic.setTool,
  }
}
