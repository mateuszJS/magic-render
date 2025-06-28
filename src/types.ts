export interface Point {
  x: number
  y: number
}

export type Line = [Point, Point]
export type QuadraticBezier = [Point, Point, Point]
export type CubicBezier = [Point, Point, Point, Point]
export type Segment = Line | QuadraticBezier | CubicBezier

export interface HTMLInputEvent extends Event {
  target: HTMLInputElement & EventTarget
}
