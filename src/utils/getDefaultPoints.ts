import { PointUV } from 'types'
import clamp from 'utils/clamp'

export default function getDefaultPoints(
  texWidth: number,
  texHeight: number,
  projectWidth: number,
  projectHeight: number
): PointUV[] {
  const scale = getDefaultTextureScale(texWidth, texHeight, projectWidth, projectHeight)
  const scaledWidth = texWidth * scale
  const scaledHeight = texHeight * scale
  const paddingX = (projectWidth - scaledWidth) * 0.5
  const paddingY = (projectHeight - scaledHeight) * 0.5

  return [
    { x: paddingX, y: paddingY + scaledHeight, u: 0, v: 1 },
    { x: paddingX + scaledWidth, y: paddingY + scaledHeight, u: 1, v: 1 },
    { x: paddingX + scaledWidth, y: paddingY, u: 1, v: 0 },
    { x: paddingX, y: paddingY, u: 0, v: 0 },
  ]
}

/**
 * Returns visualy pleasant size of texture, to make sure it doesn't overflow canvas but also is not too small to manipulate
 */
function getDefaultTextureScale(
  texWidth: number,
  texHeight: number,
  projectWidth: number,
  projectHeight: number
) {
  const heightDiff = projectHeight - texHeight
  const widthDiff = projectWidth - texWidth

  if (heightDiff < widthDiff) {
    const height = clamp(texHeight, projectHeight * 0.2, projectHeight * 0.8)
    return height / texHeight
  }

  const width = clamp(texWidth, projectWidth * 0.2, projectWidth * 0.8)
  return width / texWidth
}
