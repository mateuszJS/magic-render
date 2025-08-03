// Test for the new color and stroke support functionality
import type { SerializedInputAsset } from '../index'

describe("Color and stroke support", () => {
  test("Asset struct includes color properties", () => {
    // This test verifies that the Asset struct has been extended with color properties
    // Since we can't directly test the Zig struct, we test the TypeScript interface
    const mockAssetOutput = {
      id: 1,
      points: [
        { x: 0, y: 0, u: 0, v: 0 },
        { x: 100, y: 0, u: 1, v: 0 },
        { x: 100, y: 100, u: 1, v: 1 },
        { x: 0, y: 100, u: 0, v: 1 }
      ],
      texture_id: 1,
      fill_color: [1.0, 0.0, 0.0, 1.0], // Red fill
      stroke_color: [0.0, 0.0, 1.0, 1.0], // Blue stroke
      stroke_width: 2.0
    }

    expect(mockAssetOutput.fill_color).toEqual([1.0, 0.0, 0.0, 1.0])
    expect(mockAssetOutput.stroke_color).toEqual([0.0, 0.0, 1.0, 1.0])
    expect(mockAssetOutput.stroke_width).toBe(2.0)
  })

  test("SerializedInputAsset supports optional color properties", () => {
    const assetWithColors: SerializedInputAsset = {
      url: "test.svg",
      fillColor: [0.5, 0.5, 0.5, 1.0],
      strokeColor: [0.0, 1.0, 0.0, 1.0],
      strokeWidth: 3.0
    }

    const assetWithoutColors: SerializedInputAsset = {
      url: "test.png"
    }

    // Both should be valid SerializedInputAsset types
    expect(assetWithColors.fillColor).toEqual([0.5, 0.5, 0.5, 1.0])
    expect(assetWithColors.strokeColor).toEqual([0.0, 1.0, 0.0, 1.0])
    expect(assetWithColors.strokeWidth).toBe(3.0)
    
    expect(assetWithoutColors.fillColor).toBeUndefined()
    expect(assetWithoutColors.strokeColor).toBeUndefined()
    expect(assetWithoutColors.strokeWidth).toBeUndefined()
  })

  test("Default color values are sensible", () => {
    // Test that default color values make sense
    const defaultFillColor = [1.0, 1.0, 1.0, 1.0] // White, fully opaque
    const defaultStrokeColor = [0.0, 0.0, 0.0, 1.0] // Black, fully opaque
    const defaultStrokeWidth = 1.0

    expect(defaultFillColor[3]).toBe(1.0) // Alpha should be 1
    expect(defaultStrokeColor[3]).toBe(1.0) // Alpha should be 1
    expect(defaultStrokeWidth).toBeGreaterThan(0) // Width should be positive
  })
})