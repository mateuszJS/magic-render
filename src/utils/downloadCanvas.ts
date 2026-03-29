export function downloadCanvas(canvas: HTMLCanvasElement) {
  const link = document.createElement('a')
  link.download = 'filename.png'
  link.href = canvas.toDataURL('image/png')
  link.click()
}
