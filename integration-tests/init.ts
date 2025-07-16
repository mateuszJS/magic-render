import type { Page } from '@playwright/test'
import { expect } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from 'url'
// import { SerializedAsset } from 'index'
// import SampleImg from './image-sample.png'

const PAGE_WIDTH = 1000
const PAGE_HEIGHT = 700
let page: Page
let move: (x: number, y: number) => Promise<void>
let canvasBox: { x: number; y: number; width: number; height: number }

interface SerializedAsset {
  id: number
  points: { u: number; v: number; x: number; y: number }[]
  url: string
}

export const TransformHandle = {
  TOP_LEFT: 0,
  TOP_RIGHT: 1,
  BOTTOM_RIGHT: 2,
  BOTTOM_LEFT: 3,
}

export default async function init(receivedPage: Page) {
  page = receivedPage
  // and it produces different screenshot name base on operating system
  // while we want to make app consistent on all operating systems

  // To finally check if WebGPU is supported
  // await page.goto('https://webgpureport.org/');
  // await expect(page).toHaveScreenshot('webgpu-report.png');

  await page.setViewportSize({ width: PAGE_WIDTH, height: PAGE_HEIGHT })
  await page.goto('/')
  await page.waitForLoadState('networkidle')
  await page.evaluate(() =>
    window.addEventListener('mousemove', (e) => console.log(e.clientX, e.clientY))
  ) // to display cursor position during debugging
  // helps to copy position here

  const canvas = (await page.$('canvas'))!
  canvasBox = (await canvas.boundingBox())!

  move = async (x: number, y: number) => {
    await page.mouse.move(x + canvasBox.x, y + canvasBox.y)
  }

  return {
    getAssetsState,
    uploadAsset,
    resizeAsset,
    selectAsset,
  }
}

async function getAssetsState(): Promise<SerializedAsset[]> {
  const isProcessingEventsEl = page.locator('#is-processing-events')
  await expect(isProcessingEventsEl).toHaveText('false')

  const assetsSnapshot = await page.evaluate(() => window.assetsSnapshot)
  return assetsSnapshot
}

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const testImagePath = path.join(__dirname, './image-sample.png')

async function uploadAsset() {
  const fileInput = (await page.$('input[type="file"]'))!
  await fileInput.setInputFiles(testImagePath)
  const assets = await getAssetsState()
  return assets[assets.length - 1] // return the last uploaded asset
}

async function selectAsset({ points }: SerializedAsset) {
  await move((points[0].x + points[1].x) / 2, canvasBox.height - (points[0].y + points[3].y) / 2)
  await page.mouse.down()
  await page.mouse.up()
}

// handles are counted clock-wise starting from top left corner
async function resizeAsset(
  { points }: SerializedAsset,
  width: number,
  height: number,
  handle: number
) {
  const currentWidth = Math.abs(points[0].x - points[1].x)
  const currentHeight = Math.abs(points[0].y - points[3].y) // (canvasHeight - 140)
  const directionX =
    handle === TransformHandle.TOP_LEFT || handle === TransformHandle.BOTTOM_LEFT ? 1 : -1
  const directionY =
    handle === TransformHandle.TOP_LEFT || handle === TransformHandle.TOP_RIGHT ? 1 : -1

  await move(points[handle].x, canvasBox.height - points[handle].y)
  await page.mouse.down()
  await move(
    points[handle].x + (currentWidth - width) * directionX,
    canvasBox.height - points[handle].y + (currentHeight - height) * directionY
  )
  await page.mouse.up()
}
