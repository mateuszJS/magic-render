// npm run test-e2e -- initial-images.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'
import { fileURLToPath } from 'url'
import path from 'path'

test('initial images', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)

  const __dirname = path.dirname(fileURLToPath(import.meta.url))
  const testImagePaths = [
    path.join(__dirname, '../image-sample.png'),
    path.join(__dirname, '../another-image-sample.jpg'),
  ]

  const fileInput = (await page.$('#start-project-from-images'))!
  await fileInput.setInputFiles(testImagePaths)
  const assets = await utils.getAssetsState()
  expect(assets.length).toBe(2)
})
