// npm run test-e2e -- history.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'

test('asset selection', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const undoBtn = page.locator('#undo-btn')!
  const redoBtn = page.locator('#redo-btn')!
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
