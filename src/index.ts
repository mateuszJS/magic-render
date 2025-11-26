import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import setupDevice, { device, presentationFormat } from 'WebGPU/device'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import * as Logic from './logic/index.zig'
import initMouseController, { camera } from 'pointer'
import getDefaultPoints from 'utils/getDefaultPoints'
import * as Textures from 'textures'
import throttle from 'utils/throttle'
import generatePreview from 'WebGPU/generatePreview'
import * as Typing from 'typing'
import * as Fonts from 'fonts'
import {
  CreatorTool,
  Id,
  PointUV,
  ProjectSnapshot,
  Asset,
  ShapeProps,
  TypoProps,
  ZigAsset,
  ZigProjectSnapshot,
} from './types'
export * from './types'
import { destroyCanvasTextures } from 'getCanvasRenderDescriptor'
import setCamera from 'utils/setCamera'
import { toBounds, toShapeProps, toTypoProps, toZigShapeProps } from 'convert'
import * as CustomPrograms from 'customPrograms'

export interface CreatorAPI {
  addImage: (url: string) => void
  setSnapshot: (snapshot: ProjectSnapshot, withSnapshot: boolean) => Promise<void>
  removeAsset: VoidFunction
  destroy: VoidFunction
  setTool: (tool: CreatorTool) => void
  // we need to obtain live update!
  updateAssetTypoProps: (props: TypoProps, commit: boolean) => void // updates typography properties of selected asset
  updateAssetProps: (props: ShapeProps, commit: boolean) => void // updates properties of selected asset
  updateAssetBounds: (bounds: PointUV[], commit: boolean) => void // updates bounds of selected asset
  INFINITE_DISTANCE_THRESHOLD: number // threshold value for considering a distance as "infinite" in SDF fill effects
  INFINITE_DISTANCE: number // maximum f32 value, used for SDF fill effects
}

const NO_ASSET_ID = 0 // used when we don't have asset id yet

export default async function initCreator(
  initialProjectWidth: number, // we could also set size along setSnapshot, but
  initialProjectHeight: number, // this way we can setup camera, while resetting asset
  // we don't know if camera should be updated or not(redo/udno doesnt update camera)
  canvas: HTMLCanvasElement,
  uploadTexture: (url: string, onNewUrl: (newUrl: string) => void) => void,
  onSnapshotUpdate: (snapshot: ProjectSnapshot, commit: boolean) => void,
  onAssetSelect: (assetId: Id) => void,
  onIsProcessingFlagUpdate: (inProgress: boolean) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void,
  onUpdateTool: (tool: CreatorTool) => void,
  getFontUrl: (fontId: number) => string
): Promise<CreatorAPI> {
  let texturesLoading = 0
  let isMouseEventProcessing = false

  let snapshotWaitingCalls: Array<(snapshot: ZigProjectSnapshot) => void> | null = [] // to delay calls until initial snapshot is ready
  let lastSnapshot: ZigProjectSnapshot = {
    width: initialProjectWidth,
    height: initialProjectHeight,
    assets: [],
  }

  function updateIsProcessingFlag() {
    onIsProcessingFlagUpdate(texturesLoading > 0 || isMouseEventProcessing)
  }

  function withSnapshotReady(cb: (snapshot: ZigProjectSnapshot) => void) {
    if (snapshotWaitingCalls) {
      snapshotWaitingCalls.push(cb)
    } else {
      cb(lastSnapshot)
    }
  }

  let isDestroyed = false
  await setupDevice()

  Logic.initState(
    lastSnapshot.width,
    lastSnapshot.height,
    device.limits.maxTextureDimension2D,
    device.limits.maxBufferSize
  )

  Textures.init((texLoadings) => {
    texturesLoading = texLoadings
    updateIsProcessingFlag()
    triggerGeneratePreview()
  })

  CustomPrograms.init()

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

  let isCameraSet = false

  canvasSizeObserver(canvas, device, () => {
    if (!isCameraSet) {
      setCamera(lastSnapshot.width, lastSnapshot.height, 'fit', canvas, 30)
      isCameraSet = true
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
      lastSnapshot.width,
      lastSnapshot.height,
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

  Logic.connectOnAssetUpdateCallback((snapshot, commit) => {
    lastSnapshot = {
      width: snapshot.width,
      height: snapshot.height,
      assets: [...snapshot.assets],
    } // reassing to drop all references to Zig + make assets an actual array

    if (snapshotWaitingCalls) {
      snapshotWaitingCalls.forEach((cb) => cb(lastSnapshot))
      snapshotWaitingCalls = null
    }

    newAssetsSnapshot(commit)
  })

  function newAssetsSnapshot(commit: boolean) {
    // this function is not part of Logic.connect_on_asset_update_callback
    // only because once we update a texture url, we have to notify about the assets update
    const assets = lastSnapshot.assets.map<Asset>((asset) => {
      if ('img' in asset && asset.img) {
        const img = asset.img
        return {
          id: img.id,
          texture_id: img.texture_id,
          bounds: toBounds([...img.bounds]),
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
          bounds: toBounds([...shape.bounds]),
          props: toShapeProps(shape.props),
          sdf_texture_id: shape.sdf_texture_id,
          cache_texture_id: shape.cache_texture_id,
        }
      } else if ('text' in asset && asset.text) {
        return {
          id: asset.text.id,
          content: Typing.sanitizeContent(asset.text.content),
          bounds: toBounds([...asset.text.bounds]),
          typo_props: toTypoProps(asset.text.typo_props),
          props: toShapeProps(asset.text.props),
          sdf_texture_id: asset.text.sdf_texture_id,
        }
      } else {
        throw Error('Unknown asset type')
      }
    })

    onSnapshotUpdate({ ...lastSnapshot, assets }, commit)

    if (commit) {
      triggerGeneratePreview()
    }
  }

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

  CustomPrograms.setTriggerSnapshotsUpdateCallback((programId) => {
    withSnapshotReady((snapshot) => {
      const assetIds = snapshot.assets
        .filter((asset) => {
          const props =
            'shape' in asset ? asset.shape?.props : 'text' in asset ? asset.text?.props : null
          if (!props) return false
          return [...props.sdf_effects].some(
            (effect) => 'program_id' in effect.fill && effect.fill.program_id === programId
          )
        })
        .map((asset) => {
          if ('shape' in asset) return asset.shape.id
          if ('text' in asset) return asset.text.id
          throw Error('Only shape and text assets can have custom programs')
        })

      Logic.invalidateCache(assetIds)
    })
  })

  const addImage: CreatorAPI['addImage'] = (url) => {
    const textureId = Textures.add(url, ({ width, height, isNewTexture, shapeAssets, error }) => {
      if (error) throw error

      if (shapeAssets) {
        Logic.setSnapshot(
          {
            ...lastSnapshot,
            assets: [...lastSnapshot.assets, ...shapeAssets],
          },
          true
        )
        return
      }

      const newAsset: ZigAsset = {
        img: {
          id: NO_ASSET_ID,
          bounds: getDefaultPoints(width, height, lastSnapshot.width, lastSnapshot.height),
          texture_id: textureId,
        },
      }
      Logic.setSnapshot(
        {
          ...lastSnapshot,
          assets: [...lastSnapshot.assets, newAsset],
        },
        true
      )

      if (isNewTexture) {
        uploadTexture(url, (newUrl) => {
          Textures.updateTextureUrl(textureId, newUrl)
          newAssetsSnapshot(true)
        })
      }
    })
  }

  const { stopRAF, capturePreview } = runCreator(canvas, context, device, () => {
    isMouseEventProcessing = false
    updateIsProcessingFlag()
  })

  Fonts.loadFont(getFontUrl(0), 0)

  const setSnapshot: CreatorAPI['setSnapshot'] = async (snapshot, withSnapshot) => {
    const results = await Promise.allSettled(
      snapshot.assets.map<Promise<ZigAsset | ZigAsset[]>>(
        (asset) =>
          new Promise((resolve, reject) => {
            if ('paths' in asset) {
              // it's a shape
              return resolve({
                shape: {
                  id: asset.id || NO_ASSET_ID,
                  paths: asset.paths,
                  props: toZigShapeProps(asset.props),
                  bounds: asset.bounds,
                  sdf_texture_id: asset.sdf_texture_id || Textures.createSDF(),
                  cache_texture_id: asset.cache_texture_id || null,
                },
              })
            } else if ('content' in asset) {
              const fontId = asset.typo_props.font_family_id
              Fonts.loadFont(getFontUrl(fontId), fontId)

              return resolve({
                text: {
                  id: asset.id || NO_ASSET_ID,
                  content: asset.content,
                  bounds: asset.bounds,
                  typo_props: asset.typo_props,
                  props: toZigShapeProps(asset.props),
                  sdf_texture_id: asset.sdf_texture_id,
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

            const textureId = Textures.add(
              asset.url,
              ({ width, height, isNewTexture, shapeAssets, error }) => {
                // we wait to add image once points are known. The other option was to add image first
                // with "default" points and then update it once texture is loaded.
                // However, that would cause issues with undo/redo since we would have history
                // snapshot with "default" points and then update it to the real points.

                if (error) {
                  return reject(error)
                }

                if (shapeAssets) {
                  return resolve(shapeAssets)
                }

                if (isNewTexture) {
                  uploadTexture(asset.url, (newUrl) => {
                    Textures.updateTextureUrl(textureId, newUrl)
                    newAssetsSnapshot(true)
                  })
                }

                return resolve({
                  img: {
                    id: NO_ASSET_ID,
                    bounds: getDefaultPoints(
                      width,
                      height,
                      lastSnapshot.width,
                      lastSnapshot.height
                    ),
                    texture_id: textureId, // if there is no points, then for sure there is no asset.textureId
                  },
                })
              }
            )
          })
      )
    )

    results
      .filter((result) => result.status === 'rejected')
      .forEach((result) => {
        console.error(result.reason)
      })

    const serializedAssets = results
      .filter((result) => result.status === 'fulfilled')
      .flatMap((result) => (Array.isArray(result.value) ? [...result.value] : [result.value]))

    Logic.setSnapshot({ ...snapshot, assets: serializedAssets }, withSnapshot)
    triggerGeneratePreview()
  }

  return {
    addImage,
    removeAsset: Logic.removeAsset,
    setSnapshot,
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
    updateAssetProps: (props, commit) => {
      Logic.setSelectedAssetProps(toZigShapeProps(props), commit)
    },
    updateAssetBounds: Logic.setSelectedAssetBounds,
    updateAssetTypoProps: (typoProps, commit) => {
      Fonts.loadFont(getFontUrl(typoProps.font_family_id), typoProps.font_family_id)
      Logic.setSelectedAssetTypoProps(typoProps, commit)
    },
    INFINITE_DISTANCE_THRESHOLD: Logic.INFINITE_DISTANCE * 0.9,
    // 90% of INFINITE_DISTANCE to provide a margin for floating-point errors
    INFINITE_DISTANCE: Logic.INFINITE_DISTANCE,
  }
}
