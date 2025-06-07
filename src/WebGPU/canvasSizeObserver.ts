function updateCanvasSize(
  canvas: HTMLCanvasElement,
  width: number,
  height: number,
  device: GPUDevice
) {
  canvas.width = Math.max(1, Math.min(width, device.limits.maxTextureDimension2D))
  canvas.height = Math.max(1, Math.min(height, device.limits.maxTextureDimension2D))
}

export default function canvasSizeObserver(
  canvas: HTMLCanvasElement,
  device: GPUDevice,
  callback: VoidFunction
) {
  // TODO: should we also handle window.devicePixelRatio; ?
  const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
      const canvas = entry.target as HTMLCanvasElement
      const width = entry.contentBoxSize[0].inlineSize | 0
      const height = entry.contentBoxSize[0].blockSize | 0
      updateCanvasSize(canvas, width, height, device)
      callback()
    }
  })
  observer.observe(canvas)

  // observer calls it anyway but it just happens late enough that user see a flicker
  updateCanvasSize(canvas, canvas.clientWidth, canvas.clientHeight, device)
}
