// npm run test-e2e -- update-svg-texture.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'
import path from 'path'
import { fileURLToPath } from 'url'

test('update SVG texture while resizing size of the asset', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const canvas = page.locator('canvas')

  const utils = await init(page)

  const __dirname = path.dirname(fileURLToPath(import.meta.url))
  const testImagePaths = [path.join(__dirname, '../image-star-sample.svg')]

  const fileInput = (await page.$('#start-project-from-images'))!
  await fileInput.setInputFiles(testImagePaths)

  const [asset] = await utils.getAssetsState()
  await expect(canvas).toHaveScreenshot('creator-from-initial-images.png')

  await utils.selectAsset(asset)
  await utils.moveAsset(asset, -400, 300)
  await utils.resizeAsset(asset, 800, 600, TransformHandle.BOTTOM_RIGHT)
  await expect(canvas).toHaveScreenshot('resized-asset.png')
})

test('update SVG texture while zooming in', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const canvas = page.locator('canvas')

  const utils = await init(page)

  const __dirname = path.dirname(fileURLToPath(import.meta.url))
  const testImagePaths = [path.join(__dirname, '../image-star-sample.svg')]

  const fileInput = (await page.$('#start-project-from-assets'))!
  await fileInput.setInputFiles(testImagePaths)

  const [asset] = await utils.getAssetsState()

  await expect(canvas).toHaveScreenshot('creator-from-initial-assets.png')

  await utils.selectAsset(asset)

  // zoom in
  await page.keyboard.down('Control')
  await page.mouse.wheel(0, -1000)
  await page.keyboard.up('Control')

  await expect(canvas).toHaveScreenshot('zoom-in.png')
})

test('update SVG texture right after upload single image', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const canvas = page.locator('canvas')

  const utils = await init(page)

  const __dirname = path.dirname(fileURLToPath(import.meta.url))
  const testImagePath = path.join(__dirname, '../image-star-sample.svg')

  await utils.uploadAsset(testImagePath)

  await expect(canvas).toHaveScreenshot('after-upload-image.png')
})
