import type { PointUV } from 'types'

declare global {
  interface Window {
    DocumentTouch: any
    msMaxTouchPoints: number
  }

  interface Navigator {
    msMaxTouchPoints: number
  }
}

export const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
  navigator.userAgent
)

export const MINI_SIZE = isMobile ? 40 : 100
export const MS_PER_PIXEL = 5
export const MS_PER_MINI = MINI_SIZE * MS_PER_PIXEL

export const isTouchCapable =
  'ontouchstart' in window ||
  (window.DocumentTouch && document instanceof window.DocumentTouch) ||
  navigator.maxTouchPoints > 0 ||
  window.navigator.msMaxTouchPoints > 0

export const dpr = window.devicePixelRatio

export const DEFAULT_BOUNDS: PointUV[] = [
  { x: 0, y: 1, u: 0, v: 1 },
  { x: 1, y: 1, u: 1, v: 1 },
  { x: 1, y: 0, u: 1, v: 0 },
  { x: 0, y: 0, u: 0, v: 0 },
]
