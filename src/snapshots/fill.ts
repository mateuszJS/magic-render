import * as CustomPrograms from 'customPrograms'
import { Fill, ZigFill } from 'types'
import assertUnreachable from 'utils/assertUnreachable'

export function toFill(fill: ZigFill): Fill {
  if ('solid' in fill && fill.solid) {
    return { solid: [...fill.solid] }
  }
  if ('linear' in fill && fill.linear) {
    return {
      linear: {
        start: {
          x: fill.linear.start.x,
          y: fill.linear.start.y,
        },
        end: {
          x: fill.linear.end.x,
          y: fill.linear.end.y,
        },
        stops: [...fill.linear.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    }
  }
  if ('radial' in fill && fill.radial) {
    return {
      radial: {
        start: {
          x: fill.radial.start.x,
          y: fill.radial.start.y,
        },
        end: {
          x: fill.radial.end.x,
          y: fill.radial.end.y,
        },
        radius_ratio: fill.radial.radius_ratio,
        stops: [...fill.radial.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    }
  }

  if ('program_id' in fill && typeof fill.program_id === 'number') {
    const { code, errors } = CustomPrograms.getCodeData(fill.program_id)
    return {
      program: {
        code: code,
        id: fill.program_id,
        errors: errors,
      },
    }
  }

  assertUnreachable(fill)
}

// Zigar input and output type are not compatible
// ZigFill is compatible with output, but input needs to specify only one value on enum,
// otherwise the error occurs "Only one property of SerializedFill can be given a value"
// That's why this function overrides types to ZigFill
export function toZigFill(fill: Fill): ZigFill {
  if ('solid' in fill) {
    return { solid: [...fill.solid] } as ZigFill
  }

  if ('linear' in fill) {
    return {
      linear: {
        start: {
          x: fill.linear.start.x,
          y: fill.linear.start.y,
        },
        end: {
          x: fill.linear.end.x,
          y: fill.linear.end.y,
        },
        stops: [...fill.linear.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    } as ZigFill
  }

  if ('radial' in fill) {
    return {
      radial: {
        start: {
          x: fill.radial.start.x,
          y: fill.radial.start.y,
        },
        end: {
          x: fill.radial.end.x,
          y: fill.radial.end.y,
        },
        radius_ratio: fill.radial.radius_ratio,
        stops: [...fill.radial.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    } as ZigFill
  }

  if ('program' in fill) {
    return {
      program_id: CustomPrograms.getProgramId(fill.program.id, fill.program.code),
    } as ZigFill
  }

  assertUnreachable(fill)
}
