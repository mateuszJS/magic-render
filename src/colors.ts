/**
 * Centralized color system using HSL format
 * HSL (Hue, Saturation, Lightness) provides better color relationships and easier adjustments
 */

// Color definitions in HSL format: [hue (0-360), saturation (0-100), lightness (0-100)]
export const THEME_COLORS = {
  // Primary colors
  RED: [0, 100, 50] as const,
  GREEN: [120, 39, 48] as const,
  BLUE: [240, 100, 50] as const,
  YELLOW: [60, 100, 50] as const,
  
  // Extended palette for mipmap colors
  MAGENTA: [300, 100, 62] as const,
  PURPLE: [270, 100, 62] as const,
  INDIGO: [250, 100, 50] as const,
  CYAN_BLUE: [200, 100, 50] as const,
  CYAN: [180, 100, 50] as const,
  SPRING_GREEN: [150, 100, 60] as const,
  LIME: [75, 100, 50] as const,
  ORANGE: [36, 100, 50] as const,
  
  // Neutral colors
  BLACK: [0, 0, 0] as const,
  WHITE: [0, 0, 100] as const,
}

// Type for HSL color
export type HSLColor = readonly [number, number, number]

/**
 * Convert HSL color to RGBA array (0-1 range) for WebGPU
 */
export function hslToRgba(hsl: HSLColor, alpha: number = 1): [number, number, number, number] {
  const [h, s, l] = hsl
  const hNorm = h / 360
  const sNorm = s / 100  
  const lNorm = l / 100

  const c = (1 - Math.abs(2 * lNorm - 1)) * sNorm
  const x = c * (1 - Math.abs(((hNorm * 6) % 2) - 1))
  const m = lNorm - c / 2

  let r = 0, g = 0, b = 0

  if (hNorm >= 0 && hNorm < 1/6) {
    r = c; g = x; b = 0
  } else if (hNorm >= 1/6 && hNorm < 2/6) {
    r = x; g = c; b = 0
  } else if (hNorm >= 2/6 && hNorm < 3/6) {
    r = 0; g = c; b = x
  } else if (hNorm >= 3/6 && hNorm < 4/6) {
    r = 0; g = x; b = c
  } else if (hNorm >= 4/6 && hNorm < 5/6) {
    r = x; g = 0; b = c
  } else {
    r = c; g = 0; b = x
  }

  return [r + m, g + m, b + m, alpha]
}

/**
 * Convert HSL color to 8-bit RGBA array (0-255 range) for canvas/texture operations  
 */
export function hslToRgba255(hsl: HSLColor, alpha: number = 255): [number, number, number, number] {
  const [r, g, b, a] = hslToRgba(hsl, alpha / 255)
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255), Math.round(a * 255)]
}

/**
 * Convert HSL color to hex string
 */
export function hslToHex(hsl: HSLColor): string {
  const [r, g, b] = hslToRgba255(hsl)
  return `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`.toUpperCase()
}