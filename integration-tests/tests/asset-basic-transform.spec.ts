// npm run test-e2e -- asset-basic-transform.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'

test('asset performs basic transformations', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // select asset
  await utils.selectAsset(asset)
  await expect(canvas).toHaveScreenshot('select-image.png')

  // move
  await utils.moveAsset(asset, 100, 100)
  await expect(canvas).toHaveScreenshot('move-image.png')

  // rotate
  await utils.rotateAsset(asset, 100, 100)
  await expect(canvas).toHaveScreenshot('rotate-image.png')

  // scale with top middle handler
  await utils.resizeAsset(asset, 0, 100, TransformHandle.TOP_MIDDLE)
  await expect(canvas).toHaveScreenshot('use-top-scale-ui.png')

  // scale with top middle handler, reflect by x axis
  await utils.resizeAsset(asset, 0, -500, TransformHandle.TOP_MIDDLE)
  await expect(canvas).toHaveScreenshot('reflect-x-via-top-scale-ui.png')

  // rotate after vertical reflection(was issue in the past)
  await utils.rotateAsset(asset, -100, -100)
  await expect(canvas).toHaveScreenshot('rotate-after-reflect-x.png')
})
