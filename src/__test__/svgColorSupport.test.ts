import { parseSVGColors, addSVGShapeWithColors, TEST_SVG_EXAMPLES } from '../utils/svgColorSupport'

describe('SVG Color Support Utilities', () => {
  test('parseSVGColors extracts fill and stroke colors from SVG', () => {
    const result = parseSVGColors(TEST_SVG_EXAMPLES.redRectangle)
    
    expect(result).not.toBeNull()
    expect(result!.fillColor).toEqual([1.0, 0.0, 0.0, 1.0]) // Red
    expect(result!.strokeColor).toEqual([0.0, 0.0, 1.0, 1.0]) // Blue
    expect(result!.strokeWidth).toBe(2)
    expect(result!.points).toHaveLength(4)
  })

  test('parseSVGColors handles hex colors correctly', () => {
    const result = parseSVGColors(TEST_SVG_EXAMPLES.greenCircle)
    
    expect(result).not.toBeNull()
    expect(result!.fillColor).toEqual([0.0, 1.0, 0.0, 1.0]) // Green from #00ff00
    expect(result!.strokeColor).toEqual([0.0, 0.0, 0.0, 1.0]) // Black from #000000
    expect(result!.strokeWidth).toBe(3)
  })

  test('parseSVGColors handles rgba colors with transparency', () => {
    const result = parseSVGColors(TEST_SVG_EXAMPLES.transparentShape)
    
    expect(result).not.toBeNull()
    expect(result!.fillColor).toEqual([1.0, 0.0, 0.0, 0.5]) // Red with 50% alpha
    expect(result!.strokeColor).toEqual([0.0, 0.0, 0.0, 1.0]) // Black
    expect(result!.strokeWidth).toBe(1)
  })

  test('parseSVGColors returns null for invalid SVG', () => {
    const result = parseSVGColors('<invalid>xml</invalid>')
    expect(result).toBeNull()
  })

  test('parseSVGColors returns null for SVG without shapes', () => {
    const result = parseSVGColors('<svg><text>Hello</text></svg>')
    expect(result).toBeNull()
  })

  test('addSVGShapeWithColors calls addVectorShape with correct parameters', () => {
    const mockCreatorAPI = {
      addVectorShape: jest.fn()
    }

    const success = addSVGShapeWithColors(mockCreatorAPI, TEST_SVG_EXAMPLES.redRectangle)
    
    expect(success).toBe(true)
    expect(mockCreatorAPI.addVectorShape).toHaveBeenCalledWith(
      expect.any(Array), // points
      [1.0, 0.0, 0.0, 1.0], // red fill
      [0.0, 0.0, 1.0, 1.0], // blue stroke
      2 // stroke width
    )
  })

  test('addSVGShapeWithColors returns false for invalid SVG', () => {
    const mockCreatorAPI = {
      addVectorShape: jest.fn()
    }

    const success = addSVGShapeWithColors(mockCreatorAPI, '<invalid>xml</invalid>')
    
    expect(success).toBe(false)
    expect(mockCreatorAPI.addVectorShape).not.toHaveBeenCalled()
  })
})