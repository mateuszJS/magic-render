/**
 * Utility functions for color conversion and HSL color generation
 */

/**
 * Convert hex color to HSL format
 * @param hex - Hex color string (e.g., "#FF0000" or "#000")
 * @returns HSL color string (e.g., "hsl(0, 100%, 50%)")
 */
export function hexToHsl(hex: string): string {
  // Remove the hash symbol
  const cleanHex = hex.replace('#', '')
  
  // Convert 3-digit hex to 6-digit
  const fullHex = cleanHex.length === 3 
    ? cleanHex.split('').map(char => char + char).join('')
    : cleanHex
  
  // Parse RGB values
  const r = parseInt(fullHex.substr(0, 2), 16) / 255
  const g = parseInt(fullHex.substr(2, 2), 16) / 255
  const b = parseInt(fullHex.substr(4, 2), 16) / 255
  
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const diff = max - min
  
  // Calculate lightness
  const l = (max + min) / 2
  
  // Calculate saturation
  const s = diff === 0 ? 0 : diff / (1 - Math.abs(2 * l - 1))
  
  // Calculate hue
  let h = 0
  if (diff !== 0) {
    switch (max) {
      case r:
        h = (g - b) / diff + (g < b ? 6 : 0)
        break
      case g:
        h = (b - r) / diff + 2
        break
      case b:
        h = (r - g) / diff + 4
        break
    }
    h /= 6
  }
  
  // Convert to percentages and degrees
  const hDeg = Math.round(h * 360)
  const sPercent = Math.round(s * 100)
  const lPercent = Math.round(l * 100)
  
  return `hsl(${hDeg}, ${sPercent}%, ${lPercent}%)`
}

/**
 * Generate HSL color for gradient effect
 * @param index - Current index
 * @param total - Total number of colors
 * @param saturation - Saturation percentage (default: 100)
 * @param lightness - Lightness percentage (default: 50)
 * @returns HSL color string
 */
export function generateHslGradient(
  index: number, 
  total: number, 
  saturation: number = 100, 
  lightness: number = 50
): string {
  const hue = Math.round((index / total) * 360)
  return `hsl(${hue}, ${saturation}%, ${lightness}%)`
}