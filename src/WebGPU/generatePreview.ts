import setCamera from 'utils/setCamera'
import { camera } from '../pointer'
import Logic from 'logic/index.zig'

export default async function generatePreview(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  creatorCanvas: HTMLCanvasElement,
  projectWidth: number,
  projectHeight: number,
  outputWidth: number,
  outputHeight: number,
  capturePreview: (previewCtx: GPUCanvasContext, collectAndCleanup: VoidFunction) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void
) {
  const pixelDensity = creatorCanvas.width / creatorCanvas.clientWidth

  const previewCanvas = document.createElement('canvas')
  previewCanvas.width = outputWidth
  previewCanvas.height = outputHeight
  const previewContext = previewCanvas.getContext('webgpu')!

  previewContext.configure({
    device,
    format: presentationFormat,
  })

  // setup viewport for the preview
  const cameraCopy = { ...camera }
  setCamera(projectWidth, projectHeight, 'fill', previewCanvas)
  Logic.updateRenderScale(1, pixelDensity)

  const collectAndCleanup = () => {
    onPreviewUpdate(previewCanvas)
    previewContext.unconfigure()
    // roll back changes back to original
    camera.x = cameraCopy.x
    camera.y = cameraCopy.y
    camera.zoom = cameraCopy.zoom
    Logic.updateRenderScale(camera.zoom, creatorCanvas.width / creatorCanvas.clientWidth)
  }

  capturePreview(previewContext, collectAndCleanup)
}
