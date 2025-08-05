import { THEME_COLORS, hslToRgba, hslToRgba255, hslToHex } from '../colors'

describe('Color system', () => {
  it('should convert HSL to RGBA correctly', () => {
    // Test red color
    const redRgba = hslToRgba(THEME_COLORS.RED)
    expect(redRgba[0]).toBeCloseTo(1, 2) // red
    expect(redRgba[1]).toBeCloseTo(0, 2) // green
    expect(redRgba[2]).toBeCloseTo(0, 2) // blue  
    expect(redRgba[3]).toBe(1) // alpha
  })

  it('should convert HSL to 255-range RGBA correctly', () => {
    // Test yellow color
    const yellowRgba255 = hslToRgba255(THEME_COLORS.YELLOW)
    expect(yellowRgba255[0]).toBe(255) // red
    expect(yellowRgba255[1]).toBe(255) // green
    expect(yellowRgba255[2]).toBe(0) // blue
    expect(yellowRgba255[3]).toBe(255) // alpha
  })

  it('should convert HSL to hex correctly', () => {
    // Test some basic colors
    expect(hslToHex(THEME_COLORS.RED)).toBe('#FF0000')
    expect(hslToHex(THEME_COLORS.WHITE)).toBe('#FFFFFF')
    expect(hslToHex(THEME_COLORS.BLACK)).toBe('#000000')
  })

  it('should have all required theme colors defined', () => {
    expect(THEME_COLORS.RED).toBeDefined()
    expect(THEME_COLORS.GREEN).toBeDefined()
    expect(THEME_COLORS.BLUE).toBeDefined()
    expect(THEME_COLORS.YELLOW).toBeDefined()
    expect(THEME_COLORS.BLACK).toBeDefined()
    expect(THEME_COLORS.WHITE).toBeDefined()
  })

  it('should generate the expected color values for loading texture', () => {
    // Verify that our HSL colors produce the expected values
    const red = hslToRgba255(THEME_COLORS.RED)
    const yellow = hslToRgba255(THEME_COLORS.YELLOW)
    const blue = hslToRgba255(THEME_COLORS.BLUE)
    
    console.log('Loading texture colors:')
    console.log(`Red: ${JSON.stringify(red)}`)
    console.log(`Yellow: ${JSON.stringify(yellow)}`)
    console.log(`Blue: ${JSON.stringify(blue)}`)
    
    // These should match the original hardcoded values
    expect(red).toEqual([255, 0, 0, 255])
    expect(yellow).toEqual([255, 255, 0, 255])
    expect(blue).toEqual([0, 0, 255, 255])
  })

  it('should generate the expected hex colors for mipmaps', () => {
    const mipmapColors = [
      THEME_COLORS.RED,
      THEME_COLORS.MAGENTA,
      THEME_COLORS.PURPLE,
      THEME_COLORS.INDIGO,
      THEME_COLORS.CYAN_BLUE,
      THEME_COLORS.CYAN,
      THEME_COLORS.SPRING_GREEN,
      THEME_COLORS.GREEN,
      THEME_COLORS.LIME,
      THEME_COLORS.YELLOW,
      THEME_COLORS.ORANGE,
    ]

    const hexColors = mipmapColors.map(hslToHex)
    console.log('Mipmap colors:', hexColors)
    
    // Verify we have the expected number of colors and they're all valid hex
    expect(hexColors).toHaveLength(11)
    hexColors.forEach(hex => {
      expect(hex).toMatch(/^#[0-9A-F]{6}$/)
    })
  })
})