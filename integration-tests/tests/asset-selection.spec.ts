// npx playwright test asset-selection.spec.ts --debug

import { test, expect } from '@playwright/test'
import * as Utils from '../utils'
import { STATE_AFTER_UPLOAD } from '../assetStates'

test('asset selection', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const canvas = page.locator('canvas')
  const assetIdEl = page.locator('#selected-asset-id')

  const expectLastUpdate = await Utils.init(page)

  await expectLastUpdate(0, null)

  await Utils.uploadAsset(page)

  await page.waitForTimeout(1000) // wait for the upload to happen
  await expectLastUpdate(1, STATE_AFTER_UPLOAD)

  // no selected by default
  await expect(assetIdEl).toHaveText('0')

  // no selection after jsut hovering
  await page.mouse.move(550, 275)
  await page.waitForTimeout(100) // wait for the final result to test not-happy path
  await expect(assetIdEl).toHaveText('0')

  // hover shouldn't trigger asset update
  await expectLastUpdate(1, STATE_AFTER_UPLOAD)

  // update once selection happens
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('select-image.png')
  await expect(assetIdEl).toHaveText('1000')
  await expectLastUpdate(2, STATE_AFTER_UPLOAD)

  // update once selections is lost
  await page.mouse.move(100, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(assetIdEl).toHaveText('0')

  // loosing selection shouldn't trigger asset update
  await expectLastUpdate(3, STATE_AFTER_UPLOAD)
})
