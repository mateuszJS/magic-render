import { PointUV } from 'types'

export default function getDefaultPoints(
  texWidth: number,
  texHeight: number,
  projectWidth: number,
  projectHeight: number
): PointUV[] {
  const paddingX = (projectWidth - texWidth) * 0.5
  const paddingY = (projectHeight - texHeight) * 0.5

  return [
    { x: paddingX, y: paddingY + texHeight, u: 0, v: 1 },
    { x: paddingX + texWidth, y: paddingY + texHeight, u: 1, v: 1 },
    { x: paddingX + texWidth, y: paddingY, u: 1, v: 0 },
    { x: paddingX, y: paddingY, u: 0, v: 0 },
  ]
}
