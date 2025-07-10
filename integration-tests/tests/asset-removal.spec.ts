// npx playwright test asset-removal.spec.ts --debug

import { test, expect } from '@playwright/test'
import * as Utils from '../utils'

test('asset removal', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }

  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const expectLastUpdate = await Utils.init(page)
  await Utils.uploadAsset(page)
  const canvas = page.locator('canvas')
  const removeBtn = page.locator('#remove-btn')
  const assetIdEl = page.locator('#selected-asset-id')

  // select asset
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()

  await removeBtn.click()
  await expect(canvas).toHaveScreenshot('removed-image.png')
  await expect(assetIdEl).toHaveText('0')

  await expectLastUpdate(3, [])
})
