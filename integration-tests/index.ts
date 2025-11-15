import initCreator, { ProjectSnapshot } from '../src/index'

declare global {
  interface Window {
    lastSnapshot: ProjectSnapshot
  }
}

const assetsUpdatesHistory: ProjectSnapshot[] = []

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
  const assetBoundsTextarea = document.querySelector<HTMLTextAreaElement>('#asset-bounds-content')!
  const assetPropertiesTextarea =
    document.querySelector<HTMLTextAreaElement>('#asset-props-content')!
  const assetBoundsForm = document.querySelector<HTMLFormElement>('#asset-bounds-popover')!
  const assetPropsForm = document.querySelector<HTMLFormElement>('#asset-props-popover')!
  const projectSizeForm = document.querySelector<HTMLFormElement>('#project-size-popover')!

  window.lastSnapshot = {
    width: 0,
    height: 0,
    assets: [],
  }

  let currentHistoryIndex = 0
  let newTextures = 0
  const creator = await initCreator(
    window.innerWidth / 2,
    window.innerHeight / 2,
    canvas,
    (url, setNewUrl) => {
      setNewUrl(`${newTextures}-${url}`)
      newTextures++
      // if (url.startsWith('http://our-domain.com')) {
      // setNewUrl('new url')
      // }
    },
    (snapshot) => {
      window.lastSnapshot = snapshot
      // we had to implement this whole history logic because there is no way
      // to call creator.setSnapshot(snapshot) from test code file
      if (currentHistoryIndex < assetsUpdatesHistory.length - 1) {
        assetsUpdatesHistory.splice(currentHistoryIndex + 1)
      }
      assetsUpdatesHistory.push(snapshot)
      currentHistoryIndex = assetsUpdatesHistory.length - 1
      console.log(snapshot)
    },
    (assetId) => {
      selectedAssetEl.textContent = assetId.toString()
    },
    (inProgress) => {
      isProcessingEventsEl.textContent = inProgress ? 'true' : 'false'
    },
    (canvas) => {
      previewImg.src = canvas.toDataURL('image/png')
    },
    (newTool) => {
      toolsSelect.value = newTool.toString()
      console.log(`new tool: ${newTool}`)
    },
    (bounds, props) => {
      assetBoundsTextarea.value = JSON.stringify(bounds, null, 2)
      assetPropertiesTextarea.value = JSON.stringify(props, null, 2)
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

    const snapshot = {
      width: window.lastSnapshot.width,
      height: window.lastSnapshot.height,
      assets: Array.from(files).map((file) => ({
        url: URL.createObjectURL(file),
      })),
    }

    creator.setSnapshot(snapshot, true)
    startProjectInputFromImages.value = '' // reset input value to allow re-uploading the same file
  })

  const startProjectInputFromAssets = document.querySelector<HTMLInputElement>(
    '#start-project-from-assets'
  )!
  startProjectInputFromAssets.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const PROJECT_SAMPLE = {
      assets: Array.from(files).map((file) => ({
        url: URL.createObjectURL(file),
      })),
      width: 500,
      height: 500,
    }

    creator.setSnapshot(PROJECT_SAMPLE, true)
    startProjectInputFromAssets.value = '' // reset input value to allow re-uploading the same file
  })

  removeAssetBtn.addEventListener('click', () => {
    creator.removeAsset()
  })

  undoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.max(0, currentHistoryIndex - 1)
    const snapshot = assetsUpdatesHistory[currentHistoryIndex]
    creator.setSnapshot(snapshot)
    window.lastSnapshot = snapshot
  })

  redoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.min(assetsUpdatesHistory.length - 1, currentHistoryIndex + 1)
    const snapshot = assetsUpdatesHistory[currentHistoryIndex]
    creator.setSnapshot(snapshot)
    window.lastSnapshot = snapshot
  })

  toolsSelect.addEventListener('change', (event) => {
    const selectedTool = Number((event.target as HTMLSelectElement).value)
    creator.setTool(selectedTool)
  })

  sharedTextEffects.addEventListener('change', () => {
    creator.toggleSharedTextEffects()
  })

  assetPropsForm.addEventListener('submit', function (e) {
    e.preventDefault()
    const formData = new FormData(assetPropsForm)
    try {
      const newProps = JSON.parse(formData.get('code') as string)
      creator.updateAssetProps(newProps)
    } catch (e) {
      alert('Cannot parse JSON: ' + (e as Error).message)
    }
  })

  assetBoundsForm.addEventListener('submit', function (e) {
    e.preventDefault()
    const formData = new FormData(assetBoundsForm)
    try {
      const newBounds = JSON.parse(formData.get('code') as string)
      creator.updateAssetBounds(newBounds)
    } catch (e) {
      alert('Cannot parse JSON: ' + (e as Error).message)
    }
  })

  projectSizeForm.addEventListener('submit', function (e) {
    e.preventDefault()
    const formData = new FormData(projectSizeForm)
    const width = Number(formData.get('width'))
    const height = Number(formData.get('height'))
    creator.setSnapshot(
      {
        assets: window.lastSnapshot.assets,
        width,
        height,
      },
      true
    )
  })
}

test()
