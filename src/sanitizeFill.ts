export default function sanitizeFill(fill: ShapeProps['fill']): ShapeProps['fill'] {
  if ('solid' in fill && fill.solid) {
    console.log('fill.solid', fill.solid)
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
  throw Error('Unknown fill type')
}
