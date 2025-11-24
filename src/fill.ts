import { getCustomProgram, getCustomProgramId } from 'customPrograms'
import { SdfEffect, ZigSdfEffect } from 'types'
import assertUnreachable from 'utils/assertUnreachable'

export function toFill(fill: ZigSdfEffect['fill']): SdfEffect['fill'] {
  if ('solid' in fill) {
    return { solid: [...fill.solid] }
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
    }
  }
  if ('radial' in fill) {
    return {
      radial: {
        center: {
          x: fill.radial.center.x,
          y: fill.radial.center.y,
        },
        destination: {
          x: fill.radial.destination.x,
          y: fill.radial.destination.y,
        },
        radius_ratio: fill.radial.radius_ratio,
        stops: [...fill.radial.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    }
  }

  if ('program_id' in fill) {
    return { programCode: getCustomProgram(fill.program_id).code }
  }

  assertUnreachable(fill)
}

export function toZigFill(fill: SdfEffect['fill']): ZigSdfEffect['fill'] {
  if ('solid' in fill) {
    return { solid: [...fill.solid] }
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
    }
  }
  if ('radial' in fill) {
    return {
      radial: {
        center: {
          x: fill.radial.center.x,
          y: fill.radial.center.y,
        },
        destination: {
          x: fill.radial.destination.x,
          y: fill.radial.destination.y,
        },
        radius_ratio: fill.radial.radius_ratio,
        stops: [...fill.radial.stops].map((stop) => ({
          offset: stop.offset,
          color: [...stop.color],
        })),
      },
    }
  }

  if ('programCode' in fill) {
    return { program_id: getCustomProgramId(fill.programCode) }
  }

  assertUnreachable(fill)
}
