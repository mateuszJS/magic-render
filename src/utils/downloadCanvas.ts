export function downloadCanvas(canvas: HTMLCanvasElement) {
  const link = document.createElement('a')
  link.download = 'filename.png'
  console.log(canvas.width, canvas.height)
  link.href = canvas.toDataURL('image/png')
  link.click()
}
