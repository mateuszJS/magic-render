import setCamera from 'utils/setCamera'
import { camera } from '../pointer'
import Logic from 'logic/index.zig'

export default async function generatePreview(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat,
  creatorCanvas: HTMLCanvasElement,
  projectWidth: number,
  projectHeight: number,
  scaleFactor: number, // we cannot calcualted it from previewCanvas because it's not added to DOM,
  // so previewCanvas.clientWidth = 0
  capturePreview: (previewCtx: GPUCanvasContext, collectAndCleanup: VoidFunction) => void,
  onPreviewUpdate: (canvas: HTMLCanvasElement) => void
) {
  const size = 400
  const previewCanvas = document.createElement('canvas')
  previewCanvas.width = size
  previewCanvas.height = size
  const previewContext = previewCanvas.getContext('webgpu')!

  previewContext.configure({
    device,
    format: presentationFormat,
  })

  // setup viewport for the preview
  const cameraCopy = { ...camera }
  setCamera(projectWidth, projectHeight, 'fill', previewCanvas)
  Logic.updateRenderScale(scaleFactor)

  const collectAndCleanup = () => {
    onPreviewUpdate(previewCanvas)
    previewContext.unconfigure()
    // roll back changes back to original
    camera.x = cameraCopy.x
    camera.y = cameraCopy.y
    camera.zoom = cameraCopy.zoom
    Logic.updateRenderScale(creatorCanvas.width / (creatorCanvas.clientWidth * camera.zoom))
  }

  capturePreview(previewContext, collectAndCleanup)
}
