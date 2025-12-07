import { toFill, toZigFill } from 'snapshots/fill'
import { Effect, PointUV, BasicProps, TypoProps, ZigEffect } from 'types'

export function toBounds(bounds: PointUV[]): PointUV[] {
  return bounds.map((point) => ({
    x: point.x,
    y: point.y,
    u: point.u,
    v: point.v,
  }))
}

export function toEffects(effects: ZigEffect[]): Effect[] {
  return [...effects].map((effect) => ({
    dist_start: effect.dist_start,
    dist_end: effect.dist_end,
    fill: toFill(effect.fill),
  }))
}

export function toZigEffects(effects: Effect[]): ZigEffect[] {
  return effects.map((effect) => ({
    dist_start: effect.dist_start,
    dist_end: effect.dist_end,
    fill: toZigFill(effect.fill),
  }))
}

// BasicProps are shared between API & Zig
export function toBasicProps(props: BasicProps): BasicProps {
  return {
    blur: props.blur
      ? {
          x: props.blur.x,
          y: props.blur.y,
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
