// we use canvas to support ALL possible way of describing color in CSS
export default function parseCssColorToRgba(cssColor: string): [number, number, number, number] {
  // Create a temporary canvas element
  const canvas = new OffscreenCanvas(1, 1)
  const ctx = canvas.getContext('2d')!

  // Set the fillStyle to the CSS color and draw a 1x1 rectangle
  ctx.fillStyle = cssColor
  ctx.fillRect(0, 0, 1, 1)

  // Read the pixel data from the canvas
  const imageData = ctx.getImageData(0, 0, 1, 1)
  const [r, g, b, a] = imageData.data

  // Return normalized RGBA values (0-1 range)
  return [
    r / 255, // red
    g / 255, // green
    b / 255, // blue
    a / 255, // alpha
  ]
}
