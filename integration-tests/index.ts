import initCreator, { SerializedOutputAsset } from '../src/index'
import { camera } from '../src/WebGPU/pointer'

declare global {
  interface Window {
    assetsSnapshot: SerializedOutputAsset[]
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

  window.assetsSnapshot = []
  function setAssetSnapshot(assets: SerializedOutputAsset[]) {
    const scale = (canvas.width * camera.zoom) / canvas.clientWidth

    window.assetsSnapshot = assets.map((asset) => ({
      ...asset,
      points: asset.points.map((point) => ({
        ...point,
        x: point.x * scale + camera.x,
        y: point.y * scale + camera.y,
      })),
    }))
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
      points: [
        { x: 100, y: 200, u: 0, v: 1 },
        { x: 200, y: 200, u: 1, v: 1 },
        { x: 200, y: 100, u: 1, v: 0 },
        { x: 100, y: 100, u: 0, v: 0 },
      ],
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
}

test()
