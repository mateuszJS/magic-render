export interface Point {
  x: number
  y: number
}

export type Line = [Point, Point]
export type QuadraticBezier = [Point, Point, Point]
export type CubicBezier = [Point, Point, Point, Point]
export type Segment = {
  points: Line | QuadraticBezier | CubicBezier
  length: number
}

export interface HTMLInputEvent extends Event {
  target: HTMLInputElement & EventTarget
}
