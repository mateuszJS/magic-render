import { toFill, toZigFill } from 'fill'
import { PointUV, ShapeProps, TypoProps, ZigShapeProps } from 'types'

export function toBounds(bounds: PointUV[]): PointUV[] {
  return bounds.map((point) => ({
    x: point.x,
    y: point.y,
    u: point.u,
    v: point.v,
  }))
}

export function toShapeProps(props: ZigShapeProps): ShapeProps {
  return {
    sdf_effects: [...props.sdf_effects].map((effect) => ({
      dist_start: effect.dist_start,
      dist_end: effect.dist_end,
      fill: toFill(effect.fill),
    })),
    filter: props.filter?.gaussianBlur
      ? {
          gaussianBlur: {
            x: props.filter.gaussianBlur.x,
            y: props.filter.gaussianBlur.y,
          },
        }
      : null,
    opacity: props.opacity,
  }
}

export function toTypoProps(props: TypoProps): TypoProps {
  return {
    font_size: props.font_size,
    font_family_id: props.font_family_id,
    line_height: props.line_height,
    is_sdf_shared: props.is_sdf_shared,
  }
}

export function toZigShapeProps(props: ShapeProps): ZigShapeProps {
  return {
    sdf_effects: [...props.sdf_effects].map((effect) => ({
      dist_start: effect.dist_start,
      dist_end: effect.dist_end,
      fill: toZigFill(effect.fill),
    })),
    filter: props.filter?.gaussianBlur
      ? {
          gaussianBlur: {
            x: props.filter.gaussianBlur.x,
            y: props.filter.gaussianBlur.y,
          },
        }
      : null,
    opacity: props.opacity,
  }
}
