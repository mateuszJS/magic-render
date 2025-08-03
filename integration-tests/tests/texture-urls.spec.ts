// npm run test-e2e -- texture-urls.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'
import { fileURLToPath } from 'url'
import path from 'path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

test('avoids triggering upload for new textures', async ({ page }, testinfo) => {
  const utils = await init(page)

  const testImagePaths = [
    path.join(__dirname, '../image-sample.jpg'),
    path.join(__dirname, '../another-image-sample.jpg'),
  ]

  const fileInput = (await page.$('#start-project-from-images'))!
  await fileInput.setInputFiles(testImagePaths)

  const assets = await utils.getAssetsState()

  expect(assets[0].url).toMatch(/^[01]-blob:http/) // we use [01] because input with multiple fields
  expect(assets[1].url).toMatch(/^[01]-blob:http/) // doesn't maintain the order

  await utils.uploadAsset() // uploads image-sample.png, should not generate a new urls/not request uploadTexture
  const thridUploadAssets = await utils.getAssetsState()
  expect(thridUploadAssets[2].url).toMatch(/^[01]-blob:http/)
})

test("doesn't trigger texture upload while loading assets(existing project)", async ({
  page,
}, testinfo) => {
  const utils = await init(page)

  const testImagePaths = [
    path.join(__dirname, '../image-sample.jpg'),
    path.join(__dirname, '../another-image-sample.jpg'),
  ]

  const fileInput = (await page.$('#start-project-from-assets'))!
  await fileInput.setInputFiles(testImagePaths)

  const assets = await utils.getAssetsState()

  expect(assets[0].url).toMatch(/blob:http/)
  expect(assets[1].url).toMatch(/blob:http/)

  await utils.uploadAsset() // uploads image-sample.png, should not generate a new urls/not request uploadTexture
  const thridUploadAssets = await utils.getAssetsState()
  expect(thridUploadAssets[2].url).toMatch(/blob:http/)
})
