
import { test, expect } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PAGE_WIDTH = 1000
const PAGE_HEIGHT = 700

test('visible image after upload', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }

  testinfo.snapshotSuffix = '' // by default is `process.platform`

  // and it produces different screenshot name base on operating system
  // while we want to make app consistent on all operating systems

  // To finally check if WebGPU is supported
  // await page.goto('https://webgpureport.org/');
  // await expect(page).toHaveScreenshot('webgpu-report.png');

  await page.setViewportSize({ width: PAGE_WIDTH, height: PAGE_HEIGHT })
  await page.goto('/')
  await page.waitForLoadState("networkidle")

  /** =========PNG IMAGE UPLOAD============ */
  const fileInput = page.locator('input[type="file"]')
  const testImagePath = path.join(__dirname, '../image-sample.png')
  await fileInput.setInputFiles(testImagePath)

  const canvas = page.locator('canvas')
  await expect(canvas).toHaveScreenshot('after-upload.png')

  /** =========DISPLAYS BORDER AROUND HOVERED ASSET============ */
  const center = { x: PAGE_WIDTH / 2, y: PAGE_HEIGHT / 2 }
  await page.mouse.move(center.x, center.y)
  await expect(canvas).toHaveScreenshot('after-hover.png')

  /** =========IMAGE SELECTED============ */
  await page.mouse.click(center.x, center.y)
  await expect(canvas).toHaveScreenshot('after-selection.png')

  /** =========IMAGES POSITION UPDATES============ */
  await page.mouse.down()
  await page.mouse.move(300, 200)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('after-move.png')
})


