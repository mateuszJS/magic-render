export type HTMLInputEvent = Event & {
  target: HTMLInputElement & EventTarget
}

export type Point = {
  x: number
  y: number
}

export type PointUV = {
  x: number
  y: number
  u: number
  v: number
}

export type BoundingBox = {
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

export type RadialGradient = LinearGradient & {
  radius_ratio: number
}

type Program = {
  code: string
  id?: number
  errors?: CustomProgramError[]
}

export type Fill =
  | { linear: LinearGradient }
  | { radial: RadialGradient }
  | { solid: Color }
  | { program: Program }

export type Effect = {
  dist_start: number
  dist_end: number
  fill: Fill
}

// Same for Zig and Api
export type BasicProps = {
  blur: Point | null
  opacity: number
}

// Same for Zig and API
export type TypoProps = {
  font_size: number
  font_family_id: number
  line_height: number
  is_sdf_shared: boolean
}

/* type WITHOUT prefix "Zig" are used in API */

export type Image = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  bounds?: PointUV[]
  url: string
  texture_id?: number
}

export type Shape = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  paths: Point[][]
  bounds: PointUV[]
  props: BasicProps
  effects: Effect[]
  sdf_texture_id?: number
  cache_texture_id?: number | null
}

export type Text = {
  id?: number // not needed while loading project but useful for undo/redo to maintain selection
  content: string
  bounds: PointUV[]
  props: BasicProps
  effects: Effect[]
  typo_props: TypoProps
  sdf_texture_id: number | null
}

export type Asset = Image | Shape | Text

export type ProjectSnapshot = {
  width: number
  height: number
  assets: Asset[]
}

export enum CreatorTool {
  SelectAsset = 0,
  DrawBezierCurve = 1,
  SelectNode = 2,
  Text = 3,
}

/* type with prefix "Zig" mirrors the data coming from/to the zig module */

export type ZigFill = OneOf<{
  solid: Color
  linear: LinearGradient
  radial: RadialGradient
  program_id: number
}>

export type ZigEffect = {
  dist_start: number
  dist_end: number
  fill: ZigFill
}

type ZigImage = {
  id: number
  bounds: PointUV[]
  texture_id: number
}

type ZigShape = {
  id: number
  paths: Point[][]
  bounds: PointUV[]
  props: BasicProps
  effects: ZigEffect[]
  sdf_texture_id: number
  cache_texture_id: number | null
}

type ZigText = {
  id: number
  content: string | null
  bounds: PointUV[]
  props: BasicProps
  effects: ZigEffect[]
  typo_props: TypoProps
  sdf_texture_id: number | null
}

export type ZigAsset = { img: ZigImage } | { shape: ZigShape } | { text: ZigText }

export type ZigProjectSnapshot = {
  width: number
  height: number
  assets: ZigAsset[]
}

export type CustomProgramError = {
  length: number
  lineNum: number
  linePos: number
  message: string
  offset: number
}

export type CreatorAPI = {
  addImages: (urls: string[]) => Promise<void>
  setSnapshot: (snapshot: ProjectSnapshot, withSnapshot: boolean) => Promise<void>
  removeAsset: VoidFunction
  destroy: VoidFunction
  setTool: (tool: CreatorTool) => void
  // we need to obtain live update!
  updateAssetTypoProps: (props: TypoProps, commit: boolean) => void // updates typography properties of selected asset
  updateAssetProps: (props: BasicProps, commit: boolean) => void // updates basic properties of selected asset
  updateAssetEffects: (effects: Effect[], commit: boolean) => void // updates only effects of selected asset
  updateAssetBounds: (bounds: PointUV[], commit: boolean) => void // updates bounds of selected asset
  download: VoidFunction // triggers download of the current canvas content as an image
  INFINITE_DISTANCE_THRESHOLD: number // threshold value for considering a distance as "infinite" in SDF fill effects
  INFINITE_DISTANCE: number // maximum f32 value, used for SDF fill effects
}
