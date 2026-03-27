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
  Asset,
  CreatorAPI,
  CreatorTool,
  Id,
  ProjectSnapshot,
  ZigAsset,
  ZigProjectSnapshot,
} from './types'
import { destroyCanvasTextures } from 'getCanvasRenderDescriptor'
import setCamera from 'utils/setCamera'
import { toZigEffects, toZigProps } from 'snapshots/convert'
import * as CustomPrograms from 'customPrograms'
import * as Snapshots from 'snapshots/snapshots'
import toZigAsset from 'snapshots/toZigAsset'
import { NO_ASSET_ID } from 'consts'

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
  const abortController = new AbortController()

  function updateIsProcessingFlag() {
    onIsProcessingFlagUpdate(texturesLoading > 0 || isMouseEventProcessing)
  }

  let isDestroyed = false
  await setupDevice()
  Snapshots.init(initialProjectWidth, initialProjectHeight)

  Logic.initState(
    Snapshots.lastSnapshot.width,
    Snapshots.lastSnapshot.height,
    device.limits.maxTextureDimension2D,
    device.limits.maxBufferSize
  )

  Textures.init((texLoadings) => {
    texturesLoading = texLoadings
    updateIsProcessingFlag()
    triggerGeneratePreview()
  })

  const onProgramUpdate = (programId: number) => {
    Snapshots.withSnapshotReady((snapshot) => {
      const assetIds = CustomPrograms.getAssetIdsByProgramId(snapshot.assets, programId)
      Logic.invalidateCache(assetIds)
    })
  }

  const onProgramError = () => {
    Snapshots.withSnapshotReady((snapshot) => {
      // our aim is to notify UI about errors
      // Nothing has changed, so no error were provided!
      const assetsWithErrors = CustomPrograms.getAssetsWithError(snapshot.assets)
      onSnapshotUpdate(
        {
          ...snapshot,
          assets: assetsWithErrors,
        },
        false
      )
    })
  }

  CustomPrograms.init(onProgramUpdate, onProgramError)
  Fonts.init(getFontUrl)

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
    console.log('updateRenderScale')
    console.log('canvas.width', canvas.width)
    console.log('canvas.clientWidth', canvas.clientWidth)
    console.log('camera.zoom', camera.zoom)
    Logic.updateRenderScale(camera.zoom, canvas.clientWidth / canvas.width)
  }

  let isCameraSet = false

  canvasSizeObserver(canvas, device, () => {
    if (!isCameraSet) {
      setCamera(Snapshots.lastSnapshot.width, Snapshots.lastSnapshot.height, 'fit', canvas, 30)
      isCameraSet = true
    }
    updateRenderScale()
  })

  initPrograms(device, presentationFormat)

  initMouseController(
    canvas,
    updateRenderScale,
    () => {
      isMouseEventProcessing = true
      updateIsProcessingFlag()
    },
    abortController.signal
  )

  const throttledPreviewGenerator = throttle(() => {
    if (isDestroyed || texturesLoading > 0) return

    generatePreview(
      device,
      presentationFormat,
      canvas,
      Snapshots.lastSnapshot.width,
      Snapshots.lastSnapshot.height,
      capturePreview,
      onPreviewUpdate
    )
  }, 1000 * 5)

  const triggerGeneratePreview = () => {
    if (texturesLoading === 0) {
      throttledPreviewGenerator()
    }
  }

  const onAssetUpdate = (snapshot: ZigProjectSnapshot, commit: boolean) => {
    Snapshots.saveSnapshot(snapshot)
    newAssetsSnapshot(commit)
  }

  Logic.glueJsGeneral(
    onAssetUpdate,
    (id) => onAssetSelect([...id] as Id),
    onUpdateTool,
    Textures.createSDF,
    Textures.createComputeDepthTexture,
    Fonts.getCharData,
    Fonts.getKerning
  )

  function newAssetsSnapshot(commit: boolean) {
    // this function is not part of Logic.connect_on_asset_update_callback
    // only because once we update a texture url, we have to notify about the assets update
    onSnapshotUpdate(Snapshots.lastSnapshot, commit)
    if (commit) {
      triggerGeneratePreview()
    }
  }

  Logic.connectTyping(
    (text: string) => Typing.enable(text, canvas),
    Typing.disable,
    Typing.updateContent,
    Typing.updateSelection
  )

  const addImages: CreatorAPI['addImages'] = async (urls) => {
    const results = await Promise.allSettled(
      urls.map<Promise<Asset | Asset[]>>(
        (url) =>
          new Promise((resolve, reject) => {
            const textureId = Textures.add(
              url,
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
                  uploadTexture(url, (newUrl) => {
                    Textures.updateTextureUrl(textureId, newUrl)
                    newAssetsSnapshot(true)
                  })
                }

                return resolve({
                  id: NO_ASSET_ID,
                  bounds: getDefaultPoints(
                    width,
                    height,
                    Snapshots.lastSnapshot.width,
                    Snapshots.lastSnapshot.height
                  ),
                  texture_id: textureId, // if there is no points, then for sure there is no asset.textureId
                  url,
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

    Snapshots.withSnapshotReady((snapshot) => {
      const assets = [...snapshot.assets, ...serializedAssets].map<ZigAsset>(toZigAsset)
      Logic.setSnapshot({ ...snapshot, assets }, true)
      triggerGeneratePreview()
    })
  }

  const { stopRAF, capturePreview } = runCreator(canvas, context, device, () => {
    isMouseEventProcessing = false
    updateIsProcessingFlag()
  })

  Fonts.loadFont(0)

  const setSnapshot: CreatorAPI['setSnapshot'] = async (snapshot, withSnapshot) => {
    const assets = snapshot.assets.map<ZigAsset>(toZigAsset)
    Logic.setSnapshot({ ...snapshot, assets }, withSnapshot)
    triggerGeneratePreview()
  }

  return {
    addImages,
    removeAsset: Logic.removeAsset,
    setSnapshot,
    destroy: () => {
      isDestroyed = true
      abortController.abort()
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
      Logic.setSelectedAssetProps(toZigProps(props), commit)
    },
    updateAssetEffects: (effects, commit) => {
      Logic.setSelectedAssetEffects(toZigEffects(effects), commit)
    },
    updateAssetBounds: Logic.setSelectedAssetBounds,
    updateAssetTypoProps: (typoProps, commit) => {
      Fonts.loadFont(typoProps.font_family_id)
      Logic.setSelectedAssetTypoProps(typoProps, commit)
    },
    INFINITE_DISTANCE_THRESHOLD: Logic.INFINITE_DISTANCE * 0.9,
    // 90% of INFINITE_DISTANCE to provide a margin for floating-point errors
    INFINITE_DISTANCE: Logic.INFINITE_DISTANCE,
  }
}
