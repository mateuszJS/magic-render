export default function getSvgSource(svgSrc: string) {
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')!
  const img = new Image()
  img.onload = function () {
    ctx.drawImage(img, 0, 0)
  }
  img.src = svgSrc
  return canvas
}
