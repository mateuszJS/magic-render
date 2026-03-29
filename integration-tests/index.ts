import initCreator from '../src/index'
import type { ProjectSnapshot, Shape, Image, Text } from '../src/types'
import FontEBGaramond from './EBGaramond-VariableFont_wght.ttf'
import FontGoogleSans from './GoogleSans-Regular.ttf'
import OutfitWoff2 from './Outfit.woff2'
import OutfitBoldTtf from './Outfit-Bold.ttf'
import OutfitThinTtf from './Outfit-Light.ttf'

const fontsDictionary: Record<number, string> = {
  0: FontEBGaramond,
  1: FontGoogleSans,
  2: OutfitWoff2,
  3: OutfitBoldTtf,
  4: OutfitThinTtf,
}

declare global {
  interface Window {
    getLastSnapshot: () => ProjectSnapshot
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
  const xSlider = document.querySelector<HTMLInputElement>('#x-slider')!
  const fontFamilySelect = document.querySelector<HTMLSelectElement>('#font-family-select')!

  const BLANK_SNAPSHOT = {
    width: 500,
    height: 800,
    assets: [],
  }

  function getLastSnapshot() {
    const lastSnapshot = window.localStorage.getItem('lastSnapshot')
    if (lastSnapshot) {
      return JSON.parse(lastSnapshot) as ProjectSnapshot
    }
    return BLANK_SNAPSHOT
  }

  window.getLastSnapshot = getLastSnapshot

  function setLastSnapshot(snapshot: ProjectSnapshot) {
    window.localStorage.setItem('lastSnapshot', JSON.stringify(snapshot))
  }

  let currentHistoryIndex = 0
  let newTextures = 0
  let selectedAssetId = 0
  const projectWidth = 1000
  const projectHeight = 1650
  const creator = await initCreator(
    projectWidth,
    projectHeight,
    canvas,
    (url, setNewUrl) => {
      setNewUrl(`${newTextures}-${url}`)
      newTextures++
      // if (url.startsWith('http://our-domain.com')) {
      // setNewUrl('new url')
      // }
    },
    (snapshot, commit) => {
      setLastSnapshot(snapshot)

      const selectedAsset = snapshot.assets.find((asset) => asset.id === selectedAssetId)

      if (selectedAsset) {
        assetBoundsTextarea.value = JSON.stringify(selectedAsset.bounds, null, 2)
        if ('props' in selectedAsset) {
          assetPropertiesTextarea.value = JSON.stringify(selectedAsset.props, null, 2)
        }
      }

      if (!commit) return

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
      selectedAssetId = assetId[0]

      window.getLastSnapshot().assets.some((asset) => {
        if (asset.id === selectedAssetId && 'content' in asset) {
          sharedTextEffects.checked = asset.typo_props.is_sdf_shared
          return true
        }
        return false
      })
    },
    (inProgress) => {
      isProcessingEventsEl.textContent = inProgress ? 'true' : 'false'
    },
    (canvas) => {
      previewImg.src = canvas.toDataURL('image/png')
    },
    (newTool) => {
      toolsSelect.value = newTool.toString()
    },
    (fontId) => {
      const font = fontsDictionary[fontId]
      if (!font) throw Error('Unknown font id: ' + fontId)
      return font
    }
  )

  type SerializedOutputAssetMerged = Image & Shape & Text
  const lastSnapshot = getLastSnapshot()
  const snaitizedLastSnapshot = {
    ...lastSnapshot,
    assets: (lastSnapshot.assets as SerializedOutputAssetMerged[]).map(
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      ({ id, texture_id, cache_texture_id, sdf_texture_id, ...rest }) => rest
    ),
  }

  creator.setSnapshot(snaitizedLastSnapshot, true)

  const resetProjectBtn = document.querySelector<HTMLInputElement>('#reset-project')!
  resetProjectBtn.addEventListener('click', () => {
    setLastSnapshot(BLANK_SNAPSHOT)
    window.location.reload()
  })

  const downloadCanvasBtn = document.querySelector<HTMLInputElement>('#download-canvas')!
  downloadCanvasBtn.addEventListener('click', () => {
    creator.download()
  })

  const addImageInput = document.querySelector<HTMLInputElement>('#add-image')!
  addImageInput.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const url = URL.createObjectURL(files[0])
    creator.addImages([url])

    addImageInput.value = '' // reset input value to allow re-uploading the same file
  })

  const startProjectInputFromImages = document.querySelector<HTMLInputElement>(
    '#start-project-from-images'
  )!
  startProjectInputFromImages.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
    if (!files) return

    const snapshot = {
      width: getLastSnapshot().width,
      height: getLastSnapshot().height,
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
    creator.setSnapshot(snapshot, false)
    setLastSnapshot(snapshot)
  })

  redoBtn.addEventListener('click', () => {
    currentHistoryIndex = Math.min(assetsUpdatesHistory.length - 1, currentHistoryIndex + 1)
    const snapshot = assetsUpdatesHistory[currentHistoryIndex]
    creator.setSnapshot(snapshot, false)
    setLastSnapshot(snapshot)
  })

  toolsSelect.addEventListener('change', (event) => {
    const selectedTool = Number((event.target as HTMLSelectElement).value)
    creator.setTool(selectedTool)
  })

  sharedTextEffects.addEventListener('change', () => {
    const newAssets = getLastSnapshot().assets.map((asset) => {
      if (asset.id === selectedAssetId && 'content' in asset) {
        return {
          ...asset,
          typo_props: {
            ...asset.typo_props,
            is_sdf_shared: sharedTextEffects.checked,
          },
        }
      }

      return asset
    })
    creator.setSnapshot(
      {
        ...getLastSnapshot(),
        assets: newAssets,
      },
      true
    )
  })

  assetPropsForm.addEventListener('submit', function (e) {
    e.preventDefault()
    const formData = new FormData(assetPropsForm)
    try {
      const newProps = JSON.parse(formData.get('code') as string)
      creator.updateAssetProps(newProps, true)
    } catch (e) {
      alert('Cannot parse JSON: ' + (e as Error).message)
    }
  })

  assetBoundsForm.addEventListener('submit', function (e) {
    e.preventDefault()
    const formData = new FormData(assetBoundsForm)
    try {
      const newBounds = JSON.parse(formData.get('code') as string)
      creator.updateAssetBounds(newBounds, true)
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
        assets: getLastSnapshot().assets,
        width,
        height,
      },
      true
    )
  })

  const updateX = (commit: boolean) => {
    const x = 50 - Number(xSlider.value)
    const lastCommittedSnapshot = assetsUpdatesHistory[currentHistoryIndex]
    const asset = lastCommittedSnapshot.assets.find((a) => a.id === selectedAssetId)
    if (!asset) {
      console.error('No selected asset found')
      return
    }
    const bounds = asset.bounds

    if (!bounds) throw new Error('Asset has no bounds defined')

    const newBounds = bounds.map((point) => ({
      ...point,
      x: point.x + x,
    }))
    creator.updateAssetBounds(newBounds, commit)
  }

  xSlider.addEventListener('input', () => updateX(false))
  xSlider.addEventListener('pointerup', () => updateX(true))

  fontFamilySelect.addEventListener('change', () => {
    const fontFamilyId = Number(fontFamilySelect.value)
    const lastCommittedSnapshot = assetsUpdatesHistory[currentHistoryIndex]
    const selectedAsset = lastCommittedSnapshot.assets.find((a) => a.id === selectedAssetId)

    if (!selectedAsset || !('content' in selectedAsset)) {
      console.error('No selected text asset found')
      return
    }

    creator.updateAssetTypoProps(
      {
        ...selectedAsset.typo_props,
        font_family_id: fontFamilyId,
      },
      true
    )
  })
}

test()
