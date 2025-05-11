
import { test, expect } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from "url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

test('visible image after upload', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }

  testinfo.snapshotSuffix = '' // by default is `process.platform`

  // and it produces different screenshot name base on operating system
  // while we want to make app consistent on all operating systems

  // To finally check fi WebGPU is supported
  // await page.goto('https://webgpureport.org/');
  // await expect(page).toHaveScreenshot('webgpu-report.png');

  await page.goto('/')
  await page.waitForLoadState("networkidle")

  /** =========PNG IMAGE UPLOAD============ */
  const fileInput = page.locator('input[type="file"]')
  const testImagePath = path.join(__dirname, '../image-sample.png')
  await fileInput.setInputFiles(testImagePath)

  const canvas = page.locator('canvas')
  await expect(canvas).toHaveScreenshot('after-upload.png')

  /** =========IMAGES POSITION UPDATES============ */
  const moveImgBtn = page.locator('#img-position')
  await moveImgBtn.click()
  await expect(canvas).toHaveScreenshot('after-move.png')

  /** =========DISPLAYS BORDER AROUND HOVERED ASSET============ */
  await page.mouse.move(200, 300)
  await expect(canvas).toHaveScreenshot('after-hover.png')
})


/*
npx playwright test
    Runs the end-to-end tests.

  npx playwright test --ui
    Starts the interactive UI mode.

  npx playwright test --project=chromium
    Runs the tests only on Desktop Chrome.

  npx playwright test example
    Runs the tests in a specific file.

  npx playwright test --debug
    Runs the tests in debug mode.

  npx playwright codegen
    Auto generate tests with Codegen.

We suggest that you begin by typing:

    npx playwright test
*/