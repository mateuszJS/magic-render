// npx playwright test ui-hover.spec.ts --debug

import { test, expect } from '@playwright/test'
import * as Utils from '../utils'

test('ui elements get correct highlight on hover', async ({ page }, testinfo) => {
  if (process.env.CI) {
    test.skip()
    return
  }

  testinfo.snapshotSuffix = '' // by default is `process.platform`

  await Utils.init(page)
  await Utils.uploadAsset(page)
  const canvas = page.locator('canvas')

  // displays border on hover
  await page.mouse.move(550, 275)
  await expect(canvas).toHaveScreenshot('hover-image.png')

  // displays transform border on select
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('select-image.png')

  // highlights rotation ui
  await page.mouse.move(550, 685)
  await expect(canvas).toHaveScreenshot('hover-rotation-ui.png')

  // hovers top left scale ui handler
  await page.mouse.move(340, 70)
  await expect(canvas).toHaveScreenshot('hover-top-left-scale-ui.png')

  // hovers top middle scale ui handler
  await page.mouse.move(550, 70)
  await expect(canvas).toHaveScreenshot('hover-top-middle-scale-ui.png')
})
