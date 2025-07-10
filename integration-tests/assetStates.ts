import { expect } from '@playwright/test'

export const STATE_AFTER_UPLOAD = [
  {
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
