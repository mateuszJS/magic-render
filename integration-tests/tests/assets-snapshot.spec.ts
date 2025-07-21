// npm run test-e2e -- assets-snapshot.spec.ts --debug
// npm run test-e2e -- assets-snapshot.spec.ts --update-snapshots

import { test, expect } from '@playwright/test'
import init from '../init'

const STATE_AFTER_UPLOAD = [
  {
    id: 1000,
    textureId: 1,
    points: [
      {
        u: 0,
        v: 1,
        x: 240,
        y: 630,
      },
      {
        u: 1,
        v: 1,
        x: 660,
        y: 630,
      },
      {
        u: 1,
        v: 0,
        x: 660,
        y: 70,
      },
      {
        u: 0,
        v: 0,
        x: 240,
        y: 70,
      },
    ],
    url: expect.any(String),
  },
]

test('asset selection', async ({ page }, testinfo) => {
  testinfo.snapshotSuffix = '' // by default is `process.platform`
  const assetIdEl = page.locator('#selected-asset-id')

  const utils = await init(page)
  expect(await utils.getAssetsState()).toStrictEqual([])

  await utils.uploadAsset()
  expect(await utils.getAssetsState()).toStrictEqual(STATE_AFTER_UPLOAD)

  // no selected by default
  await expect(assetIdEl).toHaveText('0')

  // no selection after jsut hovering
  await page.mouse.move(550, 275)
  await page.waitForTimeout(100) // wait for the final result to test not-happy path
  await expect(assetIdEl).toHaveText('0')

  // hover shouldn't change anythign in assets snapshot
  expect(await utils.getAssetsState()).toStrictEqual(STATE_AFTER_UPLOAD)

  // update once selection happens
  await page.mouse.move(550, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(assetIdEl).toHaveText('1000')
  expect(await utils.getAssetsState()).toStrictEqual(STATE_AFTER_UPLOAD)

  // update once selections is lost
  await page.mouse.move(100, 275)
  await page.mouse.down()
  await page.mouse.up()
  await expect(assetIdEl).toHaveText('0')

  // loosing selection shouldn't trigger asset update
  expect(await utils.getAssetsState()).toStrictEqual(STATE_AFTER_UPLOAD)
})
