const FAKE_MIPMAPS_COLORS = [
  '#FF0000',
  '#FF00C4',
  '#C400FF',
  '#1A00FF',
  '#00A2FF',
  '#00FFFF',
  '#00FF9A',
  '#24C624',
  '#CDFF00',
  '#FFF700',
  '#FFBC00',
]

const ctx = new OffscreenCanvas(0, 0).getContext('2d', { willReadFrequently: true })!

export default function createCheckedImageData(size: number, index: number): ImageData {
  ctx.canvas.width = size
  ctx.canvas.height = size
  ctx.fillStyle = index & 1 ? '#000' : '#fff'
  ctx.fillRect(0, 0, size, size)
  ctx.fillStyle = FAKE_MIPMAPS_COLORS[index % FAKE_MIPMAPS_COLORS.length]
  ctx.fillRect(0, 0, size / 2, size / 2)
  ctx.fillRect(size / 2, size / 2, size / 2, size / 2)

  ctx.fillStyle = index & 1 ? '#FFFFFF' : '#000000'
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
