// npm run test-e2e -- asset-removal.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'

test('asset removal', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  await utils.uploadAsset()
  const removeBtn = page.locator('#remove-btn')
  const assetIdEl = page.locator('#selected-asset-id')

  // select asset
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()

  await removeBtn.click()
  await expect(assetIdEl).toHaveText('0')
  expect(await utils.getAssetsState()).toStrictEqual([])
})
