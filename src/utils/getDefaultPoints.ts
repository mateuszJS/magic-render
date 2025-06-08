import clamp from 'utils/clamp'

export default function getDefaultPoints(
  img: HTMLImageElement,
  canvas: HTMLCanvasElement
): PointUV[] {
  const scale = getDefaultTextureScale(img, canvas)
  const scaledWidth = img.width * scale
  const scaledHeight = img.height * scale
  const paddingX = (canvas.width - scaledWidth) * 0.5
  const paddingY = (canvas.height - scaledHeight) * 0.5

  return [
    { x: paddingX, y: paddingY, u: 0, v: 0 },
    { x: paddingX + scaledWidth, y: paddingY, u: 1, v: 0 },
    { x: paddingX + scaledWidth, y: paddingY + scaledHeight, u: 1, v: 1 },
    { x: paddingX, y: paddingY + scaledHeight, u: 0, v: 1 },
  ]
}

/**
 * Returns visualy pleasant size of texture, to make sure it doesn't overflow canvas but also is not too small to manipulate
 */
function getDefaultTextureScale(img: HTMLImageElement, canvas: HTMLCanvasElement) {
  const heightDiff = canvas.height - img.height
  const widthDiff = canvas.width - img.width

  if (heightDiff < widthDiff) {
    const height = clamp(img.height, canvas.height * 0.2, canvas.height * 0.8)
    return height / img.height
  }

  const width = clamp(img.width, canvas.width * 0.2, canvas.width * 0.8)
  return width / img.width
}
