export default function getSvgSource(svgSrc: string) {
  return new Promise<HTMLCanvasElement>((resolve, reject) => {
    const canvas = document.createElement('canvas')
    const ctx = canvas.getContext('2d')
    if (!ctx) {
      console.error('Canvas context is not available')
      reject(new Error('Canvas context is not available'))
      return
    }

    const img = new Image()

    img.onload = function () {
      ctx.drawImage(img, 0, 0)
      resolve(canvas)
    }

    img.onerror = function (err) {
      console.error('Error loading SVG:', err)
      reject(err)
    }

    img.src = svgSrc
  })
}
