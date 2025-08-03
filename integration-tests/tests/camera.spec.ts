import { test, expect } from '@playwright/test'
import init from '../init'

test('zoom/un-zoom with keyboard only', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // Take initial screenshot
  await expect(canvas).toHaveScreenshot('initial-zoom.png')

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