// npm run test-e2e -- resize.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'

test('resize', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  await utils.selectAsset(asset)
  const viewportSize = page.viewportSize()!
  await page.setViewportSize({ width: viewportSize.width / 2, height: viewportSize.height / 2 })
  await expect(canvas).toHaveScreenshot('after resize.png')
})
