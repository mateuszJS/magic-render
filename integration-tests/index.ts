import initCreator, { SerializedOutputAsset } from '../src/index'
import { camera } from '../src/pointer'

export interface AssetBasics {
  id: number
  points: Point[]
  url: string
}

declare global {
  interface Window {
    assetsSnapshot: AssetBasics[]
  }
}

const assetsUpdatesHistory: SerializedOutputAsset[][] = [[]]

async function test() {
  const canvas = document.querySelector<HTMLCanvasElement>('canvas')!

  const selectedAssetEl = document.querySelector<HTMLSpanElement>('#selected-asset-id')!
  const isProcessingEventsEl = document.querySelector<HTMLSpanElement>('#is-processing-events')!
  const removeAssetBtn = document.querySelector<HTMLSpanElement>('#remove-btn')!
  const undoBtn = document.querySelector<HTMLSpanElement>('#undo-btn')!
  const redoBtn = document.querySelector<HTMLSpanElement>('#redo-btn')!
  const toolsSelect = document.querySelector<HTMLSelectElement>('#tools-select')!
  const previewImg = document.querySelector<HTMLImageElement>('#preview')!
  const sharedTextEffects = document.querySelector<HTMLInputElement>('#shared-text-effects')!

  window.assetsSnapshot = []
  function setAssetSnapshot(assets: SerializedOutputAsset[]) {
    const scale = (canvas.width * camera.zoom) / canvas.clientWidth

    window.assetsSnapshot = assets.map<AssetBasics>((asset) => {
      if ('paths' in asset) {
        return {
          id: asset.id,
          url: 'cache',
          points: [],
          // points:
          //   asset.cache === null
          //     ? []
          //     : asset.bounds.map((point) => ({
          //         x: point.x * scale + camera.x,
          //         y: point.y * scale + camera.y,
          //       })),
        }
      }
      return {
        id: asset.id,
        url: '',
        points: [],
        // points: asset.points.map((point) => ({
        //   x: point.x * scale + camera.x,
        //   y: point.y * scale + camera.y,
        // })),
      }
    })
  }

  let currentHistoryIndex = 0
  let newTextures = 0
  const creator = await initCreator(
    canvas,
    (url, setNewUrl) => {
      setNewUrl(`${newTextures}-${url}`)
      newTextures++
      // if (url.startsWith('http://our-domain.com')) {
      // setNewUrl('new url')
      // }
    },
    (assets) => {
      setAssetSnapshot(assets)
      // we had to implement this whole history logic because there is no way
      // to call creator.resetCanvas(newAssets) from test code file
      if (currentHistoryIndex < assetsUpdatesHistory.length - 1) {
        assetsUpdatesHistory.splice(currentHistoryIndex + 1)
      }
      assetsUpdatesHistory.push(assets)
      currentHistoryIndex = assetsUpdatesHistory.length - 1
      console.log(assets)
    },
    (assetId) => {
      selectedAssetEl.textContent = assetId.toString()
    },
    (inProgress) => {
      isProcessingEventsEl.textContent = inProgress ? 'true' : 'false'
    },
    (canvas) => {
      previewImg.src = canvas.toDataURL('image/png')
    }
  )

  const addImageInput = document.querySelector<HTMLInputElement>('#add-image')!
  addImageInput.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const url = URL.createObjectURL(files[0])
    creator.addImage(url)

    addImageInput.value = '' // reset input value to allow re-uploading the same file
  })

  const startProjectInputFromImages = document.querySelector<HTMLInputElement>(
    '#start-project-from-images'
  )!
  startProjectInputFromImages.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const urls = Array.from(files).map((file) => ({
      url: URL.createObjectURL(file),
    }))

    creator.resetAssets(urls, true)
    startProjectInputFromImages.value = '' // reset input value to allow re-uploading the same file
  })

  const startProjectInputFroMAssets = document.querySelector<HTMLInputElement>(
    '#start-project-from-assets'
  )!
  startProjectInputFroMAssets.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const PROJECT_SAMPLE = Array.from(files).map((file) => ({
      url: URL.createObjectURL(file),
      // prettier-ignore
      matrix: [
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
      ],
      width: 500,
      height: 500,
    }))

    creator.resetAssets(PROJECT_SAMPLE, true)
    startProjectInputFroMAssets.value = '' // reset input value to allow re-uploading the same file
  })

  removeAssetBtn.addEventListener('click', () => {
    creator.removeAsset()
  })

  undoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.max(0, currentHistoryIndex - 1)
    const assets = assetsUpdatesHistory[currentHistoryIndex]
    creator.resetAssets(assets)
    setAssetSnapshot(assets)
  })

  redoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.min(assetsUpdatesHistory.length - 1, currentHistoryIndex + 1)
    const assets = assetsUpdatesHistory[currentHistoryIndex]
    creator.resetAssets(assets)
    setAssetSnapshot(assets)
  })

  toolsSelect.addEventListener('change', (event) => {
    const selectedTool = Number((event.target as HTMLSelectElement).value)
    creator.setTool(selectedTool)
  })

  sharedTextEffects.addEventListener('change', () => {
    creator.toggleSharedTextEffects()
  })
}

test()
