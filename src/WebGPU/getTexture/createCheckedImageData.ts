const FAKE_MIPMAPS_COLORS = [
  'hsl(0, 100%, 50%)',      // #FF0000
  'hsl(314, 100%, 50%)',    // #FF00C4
  'hsl(283, 100%, 50%)',    // #C400FF
  'hsl(252, 100%, 50%)',    // #1A00FF
  'hsl(199, 100%, 50%)',    // #00A2FF
  'hsl(180, 100%, 50%)',    // #00FFFF
  'hsl(157, 100%, 50%)',    // #00FF9A
  'hsl(120, 59%, 44%)',     // #24C624
  'hsl(77, 100%, 50%)',     // #CDFF00
  'hsl(58, 100%, 50%)',     // #FFF700
  'hsl(44, 100%, 50%)',     // #FFBC00
]

const ctx = new OffscreenCanvas(0, 0).getContext('2d', { willReadFrequently: true })!

export default function createCheckedImageData(size: number, index: number): ImageData {
  ctx.canvas.width = size
  ctx.canvas.height = size
  ctx.fillStyle = index & 1 ? 'hsl(0, 0%, 0%)' : 'hsl(0, 0%, 100%)'
  ctx.fillRect(0, 0, size, size)
  ctx.fillStyle = FAKE_MIPMAPS_COLORS[index % FAKE_MIPMAPS_COLORS.length]
  ctx.fillRect(0, 0, size / 2, size / 2)
  ctx.fillRect(size / 2, size / 2, size / 2, size / 2)

  ctx.fillStyle = index & 1 ? 'hsl(0, 0%, 100%)' : 'hsl(0, 0%, 0%)'
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
