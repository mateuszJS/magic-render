import { test, expect } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const PAGE_WIDTH = 1000
const PAGE_HEIGHT = 700
const center = { x: PAGE_WIDTH / 2, y: PAGE_HEIGHT / 2 }

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
  await page.waitForLoadState('networkidle')
  await page.evaluate(() =>
    window.addEventListener('mousemove', (e) => console.log(e.clientX, e.clientY))
  ) // to display cursor position during debugging
  // helps to copy position here

  /** =========PNG IMAGE UPLOAD============ */
  const fileInput = page.locator('input[type="file"]')
  const testImagePath = path.join(__dirname, '../image-sample.png')
  await fileInput.setInputFiles(testImagePath)

  const canvas = page.locator('canvas')
  await expect(canvas).toHaveScreenshot('upload-image.png')

  /** =========DISPLAYS BORDER AROUND HOVERED ASSET============ */
  await page.mouse.move(center.x, center.y)
  await expect(canvas).toHaveScreenshot('hover-image.png')

  /** =========IMAGE SELECTED============ */
  await page.mouse.click(center.x, center.y)
  await expect(canvas).toHaveScreenshot('select-image.png')

  /** =========IMAGE POSITION UPDATES============ */
  await page.mouse.down()
  await page.mouse.move(300, 300)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('move-image.png')

  /** =========ROTATION UI HOVER============ */
  await page.mouse.move(340, 640)
  await expect(canvas).toHaveScreenshot('hover-rotation-ui.png')

  /** =========IMAGE ROTATION UPDATES============ */
  await page.mouse.down()
  await page.mouse.move(573, 533)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('rotate-image.png')

  /** =========TOP SCALE HOVER============ */
  await page.mouse.move(156, 95)
  await expect(canvas).toHaveScreenshot('hover-top-scale-ui.png')

  /** =========TOP SCALE USAGE============ */
  await page.mouse.down()
  await page.mouse.move(320, 264)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('use-top-scale-ui.png')

  /** =========TOP LEFT SCALE HOVER============ */
  await page.mouse.move(168, 410)
  await expect(canvas).toHaveScreenshot('hover-top-left-scale-ui.png')

  /** =========TOP LEFT SCALE USAGE============ */
  await page.mouse.down()
  await page.mouse.move(950, 400)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('use-top-left-scale-ui.png')
})
