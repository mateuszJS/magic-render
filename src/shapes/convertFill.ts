export type ShapeFill =
  | { solid: [number, number, number, number] }
  | { linear: LinearGradient }
  | { radial: RadialGradient }

interface PaperGradientFill {
  gradient: {
    radial: boolean
    stops: {
      offset: number
      color: paper.Color
    }[]
  }
  origin: { x: number; y: number }
  destination: { x: number; y: number }
}

export default function convertFill(data: paper.Color | null): ShapeFill | null {
  if (!data) return null

  if (data.gradient) {
    const fill = data as unknown as PaperGradientFill
    const stops: GradientStop[] = fill.gradient.stops.map((s) => ({
      offset: s.offset,
      color: [s.color.red, s.color.green, s.color.blue, s.color.alpha],
    }))

    if (data.gradient.radial) {
      console.log(fill)
      return {
        radial: {
          center: fill.origin,
          radius: fill.destination,
          stops,
        },
      }
    } else {
      return {
        linear: {
          start: fill.origin,
          end: fill.destination,
          stops,
        },
      }
    }
  } else {
    return {
      solid: [data.red, data.green, data.blue, data.alpha],
    }
  }
}
