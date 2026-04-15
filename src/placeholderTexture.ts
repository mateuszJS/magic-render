import { device, presentationFormat } from 'WebGPU/device'

function createTexture(
  textureData: Uint8Array<ArrayBuffer>,
  textureWidth: number,
  textureHeight: number
): GPUTexture {
  const texture = device.createTexture({
    label: 'manually crafted placeholder texture',
    size: [textureWidth, textureHeight],
    format: presentationFormat,
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

// lazy initialziation base on presentationFormat
const INITIAL_RGB_COLOR = [255, 205, 58, 255]
// if we keep just let color, we won't know if channels where already swapped or not
// and init texture is called each time user visits creator
let color = INITIAL_RGB_COLOR

// 5×5 pixel font glyphs
// prettier-ignore
const FONT: Record<string, number[][]> = {
    A: [[0,1,1,1,0],[1,0,0,0,1],[1,1,1,1,1],[1,0,0,0,1],[1,0,0,0,1]],
    D: [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0]],
    E: [[1,1,1,1,1],[1,0,0,0,0],[1,1,1,1,0],[1,0,0,0,0],[1,1,1,1,1]],
    F: [[1,1,1,1,1],[1,0,0,0,0],[1,1,1,1,0],[1,0,0,0,0],[1,0,0,0,0]],
    G: [[0,1,1,1,0],[1,0,0,0,0],[1,0,1,1,1],[1,0,0,0,1],[0,1,1,1,0]],
    I: [[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[1,1,1,1,1]],
    M: [[1,0,0,0,1],[1,1,0,1,1],[1,0,1,0,1],[1,0,0,0,1],[1,0,0,0,1]],
    N: [[1,0,0,0,1],[1,1,0,0,1],[1,0,1,0,1],[1,0,0,1,1],[1,0,0,0,1]],
    L: [[1,0,0,0,0],[1,0,0,0,0],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,1]],
    O: [[0,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[0,1,1,1,0]],
    R: [[1,1,1,1,0],[1,0,0,0,1],[1,1,1,1,0],[1,0,0,1,0],[1,0,0,0,1]],
    T: [[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0]],
    U: [[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[0,1,1,1,0]],
    X: [[1,0,0,0,1],[0,1,0,1,0],[0,0,1,0,0],[0,1,0,1,0],[1,0,0,0,1]],
    ' ': [[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0],[0,0,0,0,0]],
  }

function drawText(pixels: Uint8Array, w: number, h: number, text: string, x0: number, y0: number) {
  let x = x0
  for (const ch of text) {
    const g = FONT[ch]
    if (g) {
      for (let row = 0; row < 5; row++) {
        for (let col = 0; col < 5; col++) {
          if (g[row][col]) {
            setPixel(pixels, w, h, x + col, y0 + 4 - row)
          }
        }
      }
    }
    x += 6 // 5px glyph + 1px gap
  }
}

const getBorderPixels = (w: number, h: number) => {
  const pixels = new Uint8Array(w * h * 4)

  for (let i = 0; i < w * h; i++) {
    if (i % w === 0 || i % w === w - 1 || i < w || i > w * h - w) {
      pixels[i * 4 + 0] = color[0]
      pixels[i * 4 + 1] = color[1]
      pixels[i * 4 + 2] = color[2]
    }
    pixels[i * 4 + 3] = 255 // opaque black by default
  }

  return pixels
}

function setPixel(pixels: Uint8Array, w: number, h: number, x: number, y: number) {
  if (x < 0 || x >= w || y < 0 || y >= h) return

  const i = (y * w + x) * 4
  pixels[i] = color[0]
  pixels[i + 1] = color[1]
  pixels[i + 2] = color[2]
  pixels[i + 3] = color[3]
}

export function getLoadingTexture(): GPUTexture {
  if (presentationFormat === 'bgra8unorm') {
    color = [INITIAL_RGB_COLOR[2], INITIAL_RGB_COLOR[1], INITIAL_RGB_COLOR[0], INITIAL_RGB_COLOR[3]]
  }

  const W = 72
  const H = 40
  const pixels = getBorderPixels(W, H)

  function drawText(text: string, x0: number, y0: number) {
    let x = x0
    for (const ch of text) {
      const g = FONT[ch]
      if (g) {
        for (let row = 0; row < 5; row++)
          for (let col = 0; col < 5; col++)
            if (g[row][col]) setPixel(pixels, W, H, x + col, y0 + 4 - row)
      }
      x += 6 // 5px glyph + 1px gap
    }
  }

  // "LOADING": 7 chars × 6 - 1 = 41px; center in 72: start x=16
  drawText('LOADING', 16, 17)

  return createTexture(pixels, W, H)
}

export function getErrorTexture(): GPUTexture {
  const W = 72
  const H = 40
  const pixels = getBorderPixels(W, H)

  // "IMAGE NOT": 9 chars × 6 - 1 = 53px; center in 72: start x=10
  drawText(pixels, W, H, 'IMAGE NOT', 10, 14)
  // "FOUND": 5 chars × 6 - 1 = 29px; center in 72: start x=21
  drawText(pixels, W, H, 'FOUND', 21, 6)

  // Mario-style ? mark (20×16) centered horizontally (start col 26)
  // High y = top of screen; mark[0] is the arch top → placed at y = 35 (highest)
  // prettier-ignore
  const mark = [
    [0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0],  // wide arch top: cols 1–16
    [0,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0],  // left wall cols 1–4, right cols 13–16
    [0,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,0,0,0],  // right wall descends one more row
    [0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,0,0,0],  // diagonal: cols 11–14
    [0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0],  // cols 9–12
    [0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0],  // cols 7–10 (stem begins)
    [0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0],  // stem
    [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],  // gap
    [0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0],  // dot
    [0,0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0,0,0,0],
  ]

  for (let r = 0; r < mark.length; r++) {
    for (let c = 0; c < 20; c++) {
      if (mark[r][c]) {
        setPixel(pixels, W, H, 26 + c, 34 - r)
      }
    }
  }

  return createTexture(pixels, W, H)
}
