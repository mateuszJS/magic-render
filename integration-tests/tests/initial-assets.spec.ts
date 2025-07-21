// npm run test-e2e -- initial-assets.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'
import { fileURLToPath } from 'url'
import path from 'path'

test('initial assets', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }
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
