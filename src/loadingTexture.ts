import { THEME_COLORS, hslToRgba255 } from './colors'

export default function getLoadingTexture(device: GPUDevice): GPUTexture {
  const textureWidth = 5
  const textureHeight = 7
  const _ = hslToRgba255(THEME_COLORS.RED) // red
  const y = hslToRgba255(THEME_COLORS.YELLOW) // yellow
  const b = hslToRgba255(THEME_COLORS.BLUE) // blue
  // prettier-ignore
  const textureData = new Uint8Array([
    b, _, _, _, _,
    _, y, y, y, _,
    _, y, _, _, _,
    _, y, y, _, _,
    _, y, _, _, _,
    _, y, _, _, _,
    _, _, _, _, _,
  ].flat())

  const texture = device.createTexture({
    label: 'yellow F on red',
    size: [textureWidth, textureHeight],
    format: 'rgba8unorm',
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  })
  device.queue.writeTexture(
    { texture },
    textureData,
    { bytesPerRow: textureWidth * 4 },
    { width: textureWidth, height: textureHeight }
  )

  return texture
}
