export interface Point {
  x: number
  y: number
}

export type Line = [Point, Point]

export interface HTMLInputEvent extends Event {
  target: HTMLInputElement & EventTarget
}
