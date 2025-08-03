// Example of how to extract color information from SVG and use with the new color support
// This demonstrates the functionality that the issue was asking for

interface SVGShapeData {
  points: PointUV[]
  fillColor: number[]
  strokeColor: number[]
  strokeWidth: number
}

// Function to parse SVG color attributes and extract shape data
export function parseSVGColors(svgString: string): SVGShapeData | null {
  try {
    const parser = new DOMParser()
    const svgDoc = parser.parseFromString(svgString, 'image/svg+xml')
    
    // Look for the first path, rect, or shape element
    const shapeElement = svgDoc.querySelector('path, rect, circle, polygon')
    
    if (!shapeElement) {
      return null
    }
    
    // Extract fill color
    const fillAttr = shapeElement.getAttribute('fill') || '#ffffff'
    const fillColor = parseColorToRGBA(fillAttr)
    
    // Extract stroke color
    const strokeAttr = shapeElement.getAttribute('stroke') || '#000000'
    const strokeColor = parseColorToRGBA(strokeAttr)
    
    // Extract stroke width
    const strokeWidthAttr = shapeElement.getAttribute('stroke-width') || '1'
    const strokeWidth = parseFloat(strokeWidthAttr)
    
    // For this example, create a simple rectangle
    // In a real implementation, you'd parse the actual path geometry
    const points: PointUV[] = [
      { x: 10, y: 10, u: 0, v: 0 },
      { x: 110, y: 10, u: 1, v: 0 },
      { x: 110, y: 110, u: 1, v: 1 },
      { x: 10, y: 110, u: 0, v: 1 }
    ]
    
    return {
      points,
      fillColor,
      strokeColor,
      strokeWidth
    }
  } catch (error) {
    console.error('Error parsing SVG:', error)
    return null
  }
}

// Helper function to convert CSS color to RGBA array
function parseColorToRGBA(colorString: string): number[] {
  // Handle common CSS color formats
  colorString = colorString.trim()
  
  // Handle hex colors
  if (colorString.startsWith('#')) {
    const hex = colorString.slice(1)
    if (hex.length === 3) {
      // Short hex format #RGB
      const r = parseInt(hex[0] + hex[0], 16) / 255
      const g = parseInt(hex[1] + hex[1], 16) / 255
      const b = parseInt(hex[2] + hex[2], 16) / 255
      return [r, g, b, 1.0]
    } else if (hex.length === 6) {
      // Full hex format #RRGGBB
      const r = parseInt(hex.slice(0, 2), 16) / 255
      const g = parseInt(hex.slice(2, 4), 16) / 255
      const b = parseInt(hex.slice(4, 6), 16) / 255
      return [r, g, b, 1.0]
    }
  }
  
  // Handle rgba/rgb
  if (colorString.startsWith('rgb')) {
    const match = colorString.match(/rgba?\(([^)]+)\)/)
    if (match) {
      const values = match[1].split(',').map(v => parseFloat(v.trim()))
      const r = values[0] / 255
      const g = values[1] / 255
      const b = values[2] / 255
      const a = values.length > 3 ? values[3] : 1.0
      return [r, g, b, a]
    }
  }
  
  // Handle named colors (basic set)
  const namedColors: Record<string, number[]> = {
    'red': [1.0, 0.0, 0.0, 1.0],
    'green': [0.0, 1.0, 0.0, 1.0],
    'blue': [0.0, 0.0, 1.0, 1.0],
    'white': [1.0, 1.0, 1.0, 1.0],
    'black': [0.0, 0.0, 0.0, 1.0],
    'transparent': [0.0, 0.0, 0.0, 0.0],
    'none': [0.0, 0.0, 0.0, 0.0]
  }
  
  const lowerColor = colorString.toLowerCase()
  if (namedColors[lowerColor]) {
    return namedColors[lowerColor]
  }
  
  // Default to black if can't parse
  return [0.0, 0.0, 0.0, 1.0]
}

// Example usage function
export function addSVGShapeWithColors(creatorAPI: any, svgString: string): boolean {
  const shapeData = parseSVGColors(svgString)
  
  if (!shapeData) {
    console.error('Could not parse SVG shape data')
    return false
  }
  
  // Use the new addVectorShape API with extracted colors
  creatorAPI.addVectorShape(
    shapeData.points,
    shapeData.fillColor,
    shapeData.strokeColor,
    shapeData.strokeWidth
  )
  
  return true
}

// Test SVG examples
export const TEST_SVG_EXAMPLES = {
  redRectangle: `
    <svg viewBox="0 0 100 100">
      <rect x="10" y="10" width="80" height="80" fill="red" stroke="blue" stroke-width="2"/>
    </svg>
  `,
  
  greenCircle: `
    <svg viewBox="0 0 100 100">
      <circle cx="50" cy="50" r="40" fill="#00ff00" stroke="#000000" stroke-width="3"/>
    </svg>
  `,
  
  transparentShape: `
    <svg viewBox="0 0 100 100">
      <path d="M20 20 L80 20 L80 80 L20 80 Z" fill="rgba(255, 0, 0, 0.5)" stroke="black" stroke-width="1"/>
    </svg>
  `
}