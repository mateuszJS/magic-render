// npm run test-e2e -- ui-hover.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'

test('ui elements get correct highlight on hover', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // displays border on hover
  const moveHandle = await utils.getMoveHandle(asset)
  await utils.pointerMove(moveHandle.x, moveHandle.y)
  await expect(canvas).toHaveScreenshot('hover-image.png')

  await canvas.click()

  // highlights rotation ui
  const rotationHandle = await utils.getRotationHandle(asset)
  await utils.pointerMove(rotationHandle.x, rotationHandle.y)
  await expect(canvas).toHaveScreenshot('hover-rotation-ui.png')

  // hovers top left scale ui handler
  const transformCornerHandle = await utils.getTransformHandle(asset, TransformHandle.TOP_LEFT)
  await utils.pointerMove(transformCornerHandle.x, transformCornerHandle.y)
  await expect(canvas).toHaveScreenshot('hover-top-left-scale-ui.png')

  // hovers top middle scale ui handler
  const transformTopHandle = await utils.getTransformHandle(asset, TransformHandle.TOP_MIDDLE)
  await utils.pointerMove(transformTopHandle.x, transformTopHandle.y)
  await expect(canvas).toHaveScreenshot('hover-top-middle-scale-ui.png')
})
