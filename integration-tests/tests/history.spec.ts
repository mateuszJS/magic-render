// npm run test-e2e -- history.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'

test('history', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const undoBtn = page.locator('#undo-btn')
  const redoBtn = page.locator('#redo-btn')
  const assetIdEl = page.locator('#selected-asset-id')

  const utils = await init(page)
  const firstAsset = await utils.uploadAsset()

  await utils.selectAsset(firstAsset)
  await utils.resizeAsset(firstAsset, 200, 200, TransformHandle.BOTTOM_RIGHT)
  const stateFirstAssetTransnform = await utils.getAssetsState()

  const secondAsset = await utils.uploadAsset()
  const stateSecondAssetUpload = await utils.getAssetsState()

  await utils.selectAsset(secondAsset)
  await utils.resizeAsset(secondAsset, 200, 200, TransformHandle.BOTTOM_LEFT)
  const stateSecondAssetTransform = await utils.getAssetsState()
  await expect(assetIdEl).toHaveText('1001')

  await undoBtn.click() // undo second asset transform
  await page.waitForTimeout(1000) // wait for the history update
  expect(await utils.getAssetsState()).toStrictEqual(stateSecondAssetUpload)
  await expect(assetIdEl).toHaveText('1001')

  await undoBtn.click() // undo second asset upload
  await expect(assetIdEl).toHaveText('0')
  expect(await utils.getAssetsState()).toStrictEqual(stateFirstAssetTransnform)

  await redoBtn.click() // redo second asset upload
  expect(await utils.getAssetsState()).toStrictEqual(stateSecondAssetUpload)

  await redoBtn.click() // redo second asset upload
  expect(await utils.getAssetsState()).toStrictEqual(stateSecondAssetTransform)
})

test('history - the next update after reset_assets should be different than input of reset_assets', async ({
  page,
}, testinfo) => {
  // There was an issue where we go back in history and last_snapshot was not updated(reset_asset wasn't updating it)
  // and with next mouse event check_assets_update function was called with same data as reset_assets got
  // while should not be called at all if nothing has changed

  // this test case looks for this behaviour by checking if rolling back history was interrupted with just a mouse event(no real change in assets)

  testinfo.snapshotSuffix = ''
  const undoBtn = page.locator('#undo-btn')
  const redoBtn = page.locator('#redo-btn')

  const utils = await init(page)
  const firstAsset = await utils.uploadAsset()

  await utils.selectAsset(firstAsset)
  await utils.resizeAsset(firstAsset, 200, 200, TransformHandle.BOTTOM_RIGHT)
  const afterResizeState = await utils.getAssetsState()
  await undoBtn.click()
  await page.mouse.move(300, 300) // move pointer on canvas
  await page.mouse.move(0, 0) // so now can be move out and trigger mouse leave event
  await redoBtn.click()
  expect(await utils.getAssetsState()).toStrictEqual(afterResizeState)
})
