// npm run test-e2e -- draw-shape.spec.ts --debug

import { test, expect } from '@playwright/test'
import init from '../init'

test('draw shape', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const canvas = page.locator('canvas')

  const utils = await init(page)

  const toolSelect = (await page.$('#tools-select'))!
  await toolSelect.selectOption({ label: 'Draw Shape' })

  await utils.pointerMove(200, 100)
  await page.mouse.down()
  await utils.pointerMove(100, 200)
  await page.mouse.up()

  await utils.pointerMove(200, 500)
  await page.mouse.down()
  await page.mouse.up()

  await utils.pointerMove(500, 500)
  await page.mouse.down()
  await utils.pointerMove(600, 600)
  await page.mouse.up()

  await utils.pointerMove(500, 100)
  await page.mouse.down()
  await page.mouse.up()

  await utils.pointerMove(400, 300)
  await page.mouse.down()
  await page.mouse.up()

  await utils.pointerMove(300, 300)
  await page.mouse.down()
  await page.mouse.up()

  await utils.pointerMove(200, 100)
  await page.mouse.down()
  await page.mouse.up()

  await expect(canvas).toHaveScreenshot('drawn-shape.png')
})
