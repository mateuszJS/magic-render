// npm run test-e2e -- camera.spec.ts --debug

import { test, expect } from '@playwright/test'
import init, { TransformHandle } from '../init'

test('zoom', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // to display controls, to make sure they stay in constant size during zooms
  await utils.selectAsset(asset)

  // and to check if zooms respects pointer position
  const transformHandle = await utils.getTransformHandle(asset, TransformHandle.TOP_LEFT)
  await utils.pointerMove(transformHandle.x, transformHandle.y)

  // Two ways of scrolling:
  // with Ctrl
  await page.keyboard.down('Control')
  await page.mouse.wheel(0, 100)
  await page.keyboard.up('Control')
  await expect(canvas).toHaveScreenshot('zoom-out-with-ctrl.png')

  // with Alt
  await page.keyboard.down('Alt')
  await page.mouse.wheel(0, -1000)
  await page.keyboard.up('Alt')
  await expect(canvas).toHaveScreenshot('zoom-in-alt.png')

  await utils.moveAsset(asset, -200, -100)
  await expect(canvas).toHaveScreenshot('move-asset-after-zoom-in.png')
})

test('panning', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // to check more elements(transform envelope around the asset)
  await utils.selectAsset(asset)

  await page.mouse.wheel(0, -200)
  await expect(canvas).toHaveScreenshot('move-with-wheel.png')

  await page.keyboard.down('Space')
  await page.mouse.down()
  await page.keyboard.up('Space')
  await page.mouse.move(200, 200)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('move-with-space.png')

  await utils.moveAsset(asset, 200, -200)
  await expect(canvas).toHaveScreenshot('move-asset-after-pan.png')
})

test('panning and zoom combined', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  const asset = await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // to check more elements(transform envelope around the asset)
  await utils.selectAsset(asset)

  const transformHandle = await utils.getTransformHandle(asset, TransformHandle.TOP_LEFT)
  await utils.pointerMove(transformHandle.x, transformHandle.y)
  await page.keyboard.down('Control')
  await page.mouse.wheel(0, -100)
  await page.keyboard.up('Control')

  await page.keyboard.down('Space')
  await page.mouse.down()
  await page.mouse.move(200, 200)
  await page.mouse.up()
  await page.keyboard.up('Space')
  await expect(canvas).toHaveScreenshot('panning after zoom.png')

  await page.keyboard.down('Control')
  await page.mouse.wheel(0, -100)
  await page.keyboard.up('Control')
  await expect(canvas).toHaveScreenshot('zoom after panning after zoom.png')
})

test('zoom/un-zoom with keyboard only', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // Test zoom in with Ctrl + Plus
  await page.keyboard.down('Control')
  await page.keyboard.press('Equal') // = key (unshifted + key)
  await page.keyboard.up('Control')
  
  // Wait for zoom to take effect
  await page.waitForTimeout(100)
  await expect(canvas).toHaveScreenshot('zoom-in-ctrl-plus.png')

  // Test zoom out with Ctrl + Minus
  await page.keyboard.down('Control')
  await page.keyboard.press('Minus')
  await page.keyboard.up('Control')
  
  // Wait for zoom to take effect
  await page.waitForTimeout(100)
  await expect(canvas).toHaveScreenshot('zoom-out-ctrl-minus.png')

  // Test zoom out with Shift + Minus (new functionality)
  await page.keyboard.down('Shift')
  await page.keyboard.press('Minus')
  await page.keyboard.up('Shift')
  
  // Wait for zoom to take effect
  await page.waitForTimeout(100)
  await expect(canvas).toHaveScreenshot('zoom-out-shift-minus.png')

  // Test zoom in with Cmd key (for macOS compatibility)
  await page.keyboard.down('Meta')
  await page.keyboard.press('Equal')
  await page.keyboard.up('Meta')
  
  // Wait for zoom to take effect
  await page.waitForTimeout(100)
  await expect(canvas).toHaveScreenshot('zoom-in-cmd-plus.png')
})
