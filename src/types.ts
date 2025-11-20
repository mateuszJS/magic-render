export interface HTMLInputEvent extends Event {
  target: HTMLInputElement & EventTarget
}

export interface Point {
  x: number
  y: number
}

export interface PointUV {
  x: number
  y: number
  u: number
  v: number
}

export interface BoundingBox {
  min_x: number
  min_y: number
  max_x: number
  max_y: number
}

export type Color = [number, number, number, number]
export type Id = [number, number, number, number]

export type GradientStop = {
  color: Color
  offset: number // 0..1
}

export type LinearGradient = {
  start: Point
  end: Point
  stops: GradientStop[]
}

export type RadialGradient = {
  radius_ratio: number
  stops: GradientStop[]
  center: Point
  destination: Point
}

export type SdfEffect = {
  dist_start: number
  dist_end: number
  fill: { linear: LinearGradient } | { radial: RadialGradient } | { solid: Color }
}

export type ShapeProps = {
  sdf_effects: SdfEffect[]
  filter: { gaussianBlur: Point } | null
  opacity: number
}

export type TypoProps = {
  font_size: number
  line_height: number
  is_sdf_shared: boolean
}

export type SerializedImage = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  bounds?: PointUV[]
  url: string
  texture_id?: number
}

export type SerializedShape = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  paths: Point[][]
  props: ShapeProps
  bounds: PointUV[]
  sdf_texture_id?: number
  cache_texture_id?: number | null
}

export type SerializedText = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  content: string
  bounds: PointUV[]
  props: ShapeProps
  typo_props: TypoProps
  sdf_texture_id: number | null
}

export type SerializedAsset = SerializedImage | SerializedShape | SerializedText

export enum CreatorTool {
  SelectAsset = 0,
  DrawBezierCurve = 1,
  SelectNode = 2,
  Text = 3,
}

type ImageAsset = {
  id: number
  bounds: PointUV[]
  texture_id: number
}

type ShapeAsset = {
  id: number
  paths: Point[][]
  props: ShapeProps
  bounds: PointUV[]
  sdf_texture_id: number
  cache_texture_id: number | null
}

type TextAsset = {
  id: number
  content: string | null
  bounds: PointUV[]
  props: ShapeProps
  typo_props: TypoProps
  sdf_texture_id: number | null
}

export type ZigAsset = { img: ImageAsset } | { shape: ShapeAsset } | { text: TextAsset }

export interface ZigProjectSnapshot {
  width: number
  height: number
  assets: ZigAsset[]
}

export interface ProjectSnapshot {
  width: number
  height: number
  assets: SerializedAsset[]
}
