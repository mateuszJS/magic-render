// npm run test-e2e -- asset-basic-transform.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'

test('asset performs basic transformations', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`

  const utils = await init(page)
  await utils.uploadAsset()
  const canvas = page.locator('canvas')

  // select asset
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('select-image.png')

  // move
  await page.mouse.down()
  await page.mouse.move(650, 230)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('move-image.png')

  // rotate
  await page.mouse.move(650, 645)
  await page.mouse.down()
  await page.mouse.move(430, 570)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('rotate-image.png')

  // scale with top middle handler
  await page.mouse.move(830, 90)
  await page.mouse.down()
  await page.mouse.move(700, 240)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('use-top-scale-ui.png')

  // scale with top middle handler, reflect by x axis

  await page.mouse.move(470, 520)
  await page.mouse.down()
  await page.mouse.move(845, 70)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('reflect-x-via-top-scale-ui.png')

  // rotate after vertical reflection(was issue in the past)
  await page.mouse.move(880, 30)
  await page.mouse.down()
  await page.mouse.move(773, 332)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('rotate-after-reflect-x.png')

  // scale with top right andler
  await page.mouse.move(980, 50)
  await page.mouse.down()
  await page.mouse.move(170, 530)
  await page.mouse.up()
  await expect(canvas).toHaveScreenshot('use-top-right-scale-ui.png')
})
