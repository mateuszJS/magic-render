// npm run test-e2e -- initial-assets.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'
import { fileURLToPath } from 'url'
import path from 'path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

test('initial assets', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)

  const testImagePaths = [
    path.join(__dirname, '../image-sample.png'),
    path.join(__dirname, '../another-image-sample.jpg'),
  ]

  const fileInput = (await page.$('#start-project-from-assets'))!
  await fileInput.setInputFiles(testImagePaths)
  const assets = await utils.getAssetsState()
  expect(assets.length).toBe(2)
})
