import type { Page } from '@playwright/test'
import { expect } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from 'url'

const PAGE_WIDTH = 1000
const PAGE_HEIGHT = 700
let page: Page
let pointerMove: (x: number, y: number) => Promise<void>
let canvasBox: { x: number; y: number; width: number; height: number }

interface SerializedAsset {
  id: number
  points: { u: number; v: number; x: number; y: number }[]
  url: string
}

// SyntaxError: TypeScript enum is not supported in strip-only mode
export const TransformHandle = {
  TOP_LEFT: 0,
  TOP_MIDDLE: 0.5, // so we can call Math.floor and Math.ceil and calculate correct mid point between 0 and 1
  TOP_RIGHT: 1,
  MIDDLE_RIGHT: 1.5,
  BOTTOM_RIGHT: 2,
  BOTTOM_MIDDLE: 2.5,
  BOTTOM_LEFT: 3,
  MIDDLE_LEFT: 3.5,
}

export default async function init(receivedPage: Page) {
  page = receivedPage

  // To check in the future if WebGPU is supported
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

  pointerMove = async (x: number, y: number) => {
    await page.mouse.move(x + canvasBox.x, canvasBox.height - y + canvasBox.y)
  }

  return {
    getAssetsState,
    uploadAsset,
    resizeAsset,
    selectAsset,
    moveAsset,
    rotateAsset,
    getMoveHandle,
    getTransformHandle,
    getRotationHandle,
    pointerMove,
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
  const fileInput = (await page.$('#add-image'))!
  await fileInput.setInputFiles(testImagePath)
  const assets = await getAssetsState()
  return assets[assets.length - 1] // return the last uploaded asset
}

async function selectAsset({ points }: SerializedAsset) {
  await pointerMove((points[0].x + points[1].x) / 2, (points[0].y + points[3].y) / 2)
  await page.mouse.down()
  await page.mouse.up()
}

async function getTransformHandle(
  { id }: SerializedAsset,
  handleIdx: number /* float type index */
) {
  const { points } = await getAssetsState().then(
    (assets) => assets.find((asset) => asset.id === id)!
  )

  const handle = {
    // so if handle is int, stays same, if float, will pick two neighbours around that float
    x: (points[Math.floor(handleIdx)].x + points[Math.ceil(handleIdx)].x) / 2,
    y: (points[Math.floor(handleIdx)].y + points[Math.ceil(handleIdx)].y) / 2,
  }

  return handle
}

async function getRotationHandle({ id }: SerializedAsset) {
  const { points } = await getAssetsState().then(
    (assets) => assets.find((asset) => asset.id === id)!
  )

  const angle = Math.atan2(points[3].y - points[0].y, points[3].x - points[0].x)
  const midX = (points[2].x + points[3].x) / 2
  const midY = (points[2].y + points[3].y) / 2
  const rotateUI = {
    x: midX + Math.cos(angle) * 60,
    y: midY + Math.sin(angle) * 60,
  }

  return rotateUI
}

async function getMoveHandle({ id }: SerializedAsset) {
  const { points } = await getAssetsState().then(
    (assets) => assets.find((asset) => asset.id === id)!
  )

  return {
    x: (points[0].x + points[2].x) / 2,
    y: (points[0].y + points[2].y) / 2,
  }
}

// handles are counted clock-wise starting from top left corner
async function resizeAsset(
  asset: SerializedAsset,
  offsetWidth: number,
  offsetHeight: number,
  handleIdx: number /* float type index */
) {
  const { id } = asset
  const { points } = await getAssetsState().then(
    (assets) => assets.find((asset) => asset.id === id)!
  )

  const MAP_HANDLE_TO_DISTANCE = {
    [TransformHandle.TOP_LEFT]: [-offsetWidth, offsetHeight],
    [TransformHandle.TOP_MIDDLE]: [0, offsetHeight],
    [TransformHandle.TOP_RIGHT]: [offsetWidth, offsetHeight],
    [TransformHandle.MIDDLE_RIGHT]: [offsetWidth, 0],
    [TransformHandle.BOTTOM_RIGHT]: [offsetWidth, -offsetHeight],
    [TransformHandle.BOTTOM_MIDDLE]: [0, -offsetHeight],
    [TransformHandle.BOTTOM_LEFT]: [-offsetWidth, -offsetHeight],
    [TransformHandle.MIDDLE_LEFT]: [-offsetWidth, 0],
  }

  const handle = await getTransformHandle(asset, handleIdx)

  await pointerMove(handle.x, handle.y)
  await page.mouse.down()

  // it's going to fail if you keep reflecting an asset by any axis
  const assetAngle = Math.atan2(points[1].y - points[0].y, points[1].x - points[0].x)
  const correctedDistance = MAP_HANDLE_TO_DISTANCE[handleIdx]
  const angle = assetAngle + Math.atan2(correctedDistance[1], correctedDistance[0])
  const distance = Math.hypot(offsetWidth, offsetHeight)

  await pointerMove(handle.x + Math.cos(angle) * distance, handle.y + Math.sin(angle) * distance)
  await page.mouse.up()
}

async function moveAsset(asset: SerializedAsset, realOffsetX: number, realOffsetY: number) {
  const handle = await getMoveHandle(asset)
  await pointerMove(handle.x, handle.y)
  await page.mouse.down()
  await pointerMove(handle.x + realOffsetX, handle.y + realOffsetY)
  await page.mouse.up()
}

async function rotateAsset(asset: SerializedAsset, realOffsetX: number, realOffsetY: number) {
  const rotateUI = await getRotationHandle(asset)

  await pointerMove(rotateUI.x, rotateUI.y)
  await page.mouse.down()
  await pointerMove(rotateUI.x + realOffsetX, rotateUI.y + realOffsetY)
  await page.mouse.up()
}
