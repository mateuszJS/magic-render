import throttle from 'utils/throttle'

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

  const onResize = throttle((entry: ResizeObserverEntry) => {
    const canvas = entry.target as HTMLCanvasElement
    // Safari does not support devicePixelContentBoxSize
    const width =
      entry.devicePixelContentBoxSize?.[0].inlineSize ??
      entry.contentBoxSize[0].inlineSize * devicePixelRatio
    const height =
      entry.devicePixelContentBoxSize?.[0].blockSize ??
      entry.contentBoxSize[0].blockSize * devicePixelRatio

    updateCanvasSize(canvas, width, height, device)
    callback()

    // doing it more often causes actually worst results
    // seems like canvas starts skipping updated then
  }, 100)

  const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
      onResize(entry)
    }
  })

  try {
    observer.observe(canvas, { box: 'device-pixel-content-box' })
  } catch {
    observer.observe(canvas, { box: 'content-box' })
  }

  // observer calls it anyway but it just happens late enough that user see a flicker
  // it it just displayed for a brief second, so we don't play with devicePixelContentBoxSize or devicePixelRatio
  updateCanvasSize(canvas, canvas.clientWidth, canvas.clientHeight, device)
}
