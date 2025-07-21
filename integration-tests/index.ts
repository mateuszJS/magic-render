import initCreator, { SerializedOutputAsset } from '../src/index'

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

  window.assetsSnapshot = []
  let currentHistoryIndex = 0

  const creator = await initCreator(
    canvas,
    (assets) => {
      window.assetsSnapshot = assets
      // we had to implement this whole history logic because there is no way
      // to call creator.resetCanvas(newAssets) from test code file
      if (currentHistoryIndex === assetsUpdatesHistory.length - 1) {
        assetsUpdatesHistory.push(assets)
        currentHistoryIndex = assetsUpdatesHistory.length - 1
      }
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
    creator.addImage(URL.createObjectURL(files[0]))
    addImageInput.value = '' // reset input value to allow re-uploading the same file
  })

  const startProjectInput = document.querySelector<HTMLInputElement>('#start-project-from-images')!
  startProjectInput.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return
    creator.resetAssets(
      Array.from(files).map((file) => ({
        url: URL.createObjectURL(file),
      })),
      true
    )
    startProjectInput.value = '' // reset input value to allow re-uploading the same file
  })

  removeAssetBtn.addEventListener('click', () => {
    creator.removeAsset()
  })

  undoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.max(0, currentHistoryIndex - 1)
    const assets = assetsUpdatesHistory[currentHistoryIndex]
    creator.resetAssets(assets)
    window.assetsSnapshot = assets
  })

  redoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.min(assetsUpdatesHistory.length - 1, currentHistoryIndex + 1)
    const assets = assetsUpdatesHistory[currentHistoryIndex]
    creator.resetAssets(assets)
    window.assetsSnapshot = assets
  })
}

test()
