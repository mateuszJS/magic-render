import { THEME_COLORS, hslToHex } from '../../colors'

const FAKE_MIPMAPS_COLORS = [
  hslToHex(THEME_COLORS.RED),
  hslToHex(THEME_COLORS.MAGENTA),
  hslToHex(THEME_COLORS.PURPLE),
  hslToHex(THEME_COLORS.INDIGO),
  hslToHex(THEME_COLORS.CYAN_BLUE),
  hslToHex(THEME_COLORS.CYAN),
  hslToHex(THEME_COLORS.SPRING_GREEN),
  hslToHex(THEME_COLORS.GREEN),
  hslToHex(THEME_COLORS.LIME),
  hslToHex(THEME_COLORS.YELLOW),
  hslToHex(THEME_COLORS.ORANGE),
]

const ctx = new OffscreenCanvas(0, 0).getContext('2d', { willReadFrequently: true })!

export default function createCheckedImageData(size: number, index: number): ImageData {
  ctx.canvas.width = size
  ctx.canvas.height = size
  ctx.fillStyle = index & 1 ? hslToHex(THEME_COLORS.BLACK) : hslToHex(THEME_COLORS.WHITE)
  ctx.fillRect(0, 0, size, size)
  ctx.fillStyle = FAKE_MIPMAPS_COLORS[index % FAKE_MIPMAPS_COLORS.length]
  ctx.fillRect(0, 0, size / 2, size / 2)
  ctx.fillRect(size / 2, size / 2, size / 2, size / 2)

  ctx.fillStyle = index & 1 ? hslToHex(THEME_COLORS.WHITE) : hslToHex(THEME_COLORS.BLACK)
  ctx.font = `${size * 0.3}px serif`
  ctx.textAlign = 'center'
  ctx.textBaseline = 'middle'
  ;[
    { x: 0.25, y: 0.25 },
    { x: 0.25, y: 0.75 },
    { x: 0.75, y: 0.75 },
    { x: 0.75, y: 0.25 },
  ].forEach((p) => {
    ctx.fillText(index.toString(), p.x * size, p.y * size)
  })

  return ctx.getImageData(0, 0, size, size)
}
