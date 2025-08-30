import paper from 'paper'

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

export interface FillInfo {
  kind: 'solid' | 'linear'
  color?: [number, number, number, number]
  stops?: GradientStop[]
  gradientStart?: { x: number; y: number }
  gradientEnd?: { x: number; y: number }
}

export default function convertFill(data: paper.Color | null): FillInfo | null {
  if (!data) return null

  if (data.gradient) {
    const fill = data as unknown as PaperGradientFill
    const stops: GradientStop[] = fill.gradient.stops.map((s) => ({
      offset: s.offset,
      color: [s.color.red, s.color.green, s.color.blue, s.color.alpha],
    }))
    return {
      kind: 'linear',
      stops,
      gradientStart: fill.origin,
      gradientEnd: fill.destination,
    }
  } else {
    return {
      kind: 'solid',
      color: [data.red, data.green, data.blue, data.alpha],
    }
  }
}
