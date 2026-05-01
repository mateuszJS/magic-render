import throttle from 'utils/throttle'
import { captureCanvas } from 'WebGPU/captureCanvas'
import * as Snapshots from 'snapshots/snapshots'
import { device, presentationFormat } from 'WebGPU/setupDevice'

let isDeviceDestroyed = false
export function markDeviceDestroyed() {
  isDeviceDestroyed = true
}

let textures = 0
let fonts = 0
let programs = 0

export function updateResourcesFlag(
  type:
    | 'font-load-start'
    | 'font-load-end'
    | 'texture-load-start'
    | 'texture-load-end'
    | 'program-load-start'
    | 'program-load-end'
) {
  switch (type) {
    case 'font-load-start': {
      fonts++
      break
    }
    case 'font-load-end': {
      fonts--
      break
    }
    case 'texture-load-start': {
      textures++
      break
    }
    case 'texture-load-end': {
      textures--
      break
    }
    case 'program-load-start': {
      programs++
      break
    }
    case 'program-load-end': {
      programs--
      break
    }
  }

  safeGeneratePreview()
}

let generatePreview: VoidFunction | null = null

export function safeGeneratePreview() {
  if (textures === 0 && fonts === 0 && programs === 0) {
    generatePreview?.()
  }
}

type Params = {
  canvas: HTMLCanvasElement
  capturePreview: (previewCtx: GPUCanvasContext, collectAndCleanup: VoidFunction) => void
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void
  onResourcesLoad: VoidFunction
}

export function init({ canvas, capturePreview, onPreviewUpdate }: Params) {
  generatePreview = throttle(() => {
    if (isDeviceDestroyed) return

    captureCanvas(
      device,
      presentationFormat,
      canvas,
      Snapshots.lastSnapshot.width,
      Snapshots.lastSnapshot.height,
      400,
      400,
      capturePreview,
      onPreviewUpdate
    )
  }, 1000 * 5)
}
