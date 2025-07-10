import type { Page } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from 'url'
import { expect } from '@playwright/test'

const PAGE_WIDTH = 1000
const PAGE_HEIGHT = 700

export async function init(page: Page) {
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

  async function expectLastUpdate(
    numberOfTheUpdate: number,
    assetsUpdate: Window['testLastAssetUpdate']['assets']
  ) {
    const testLastAssetUpdate = await page.evaluate(() => window.testLastAssetUpdate)
    expect(testLastAssetUpdate).toEqual({
      calledTimes: numberOfTheUpdate,
      assets: assetsUpdate,
    })
  }

  return expectLastUpdate
}

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export async function uploadAsset(page: Page) {
  const fileInput = page.locator('input[type="file"]')
  const testImagePath = path.join(__dirname, './image-sample.png')
  await fileInput.setInputFiles(testImagePath)
}
