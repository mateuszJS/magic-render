import { camera } from 'pointer'

export default function setCamera(
  projectWidth: number,
  projectHeight: number,
  mode: 'fit' | 'fill',
  canvas: HTMLCanvasElement,
  padding = 0
) {
  const availableWidth = canvas.width - padding * 2
  const availableHeight = canvas.height - padding * 2
  const scale =
    mode === 'fit'
      ? Math.min(availableWidth / projectWidth, availableHeight / projectHeight)
      : Math.max(availableWidth / projectWidth, availableHeight / projectHeight)
  camera.x = (canvas.width - projectWidth * scale) / 2
  camera.y = (canvas.height - projectHeight * scale) / 2
  camera.zoom = scale
}
