// Mock the zig imports to avoid compilation issues in tests
jest.mock('../logic/index.zig', () => ({
  on_pointer_move: jest.fn(),
  on_pointer_leave: jest.fn(),
  on_pointer_down: jest.fn(),
  on_pointer_up: jest.fn(),
}))

// Mock global Point type
declare global {
  interface Point {
    x: number
    y: number
  }
}

import initMouseController, { camera, pointer } from '../WebGPU/pointer'

describe('Keyboard Zoom Functionality', () => {
  let canvas: HTMLCanvasElement
  let mockOnZoom: jest.Mock
  let mockOnStartProcessing: jest.Mock

  beforeEach(() => {
    // Reset camera state
    camera.x = 0
    camera.y = 0
    camera.zoom = 1
    
    // Reset pointer state
    pointer.x = 0
    pointer.y = 0
    pointer.afterPickEventsQueue = []

    // Create canvas
    canvas = document.createElement('canvas')
    canvas.width = 800
    canvas.height = 600
    document.body.appendChild(canvas)

    // Create mocks
    mockOnZoom = jest.fn()
    mockOnStartProcessing = jest.fn()

    // Initialize mouse controller
    initMouseController(canvas, mockOnZoom, mockOnStartProcessing)
  })

  afterEach(() => {
    document.body.innerHTML = ''
  })

  test('should zoom in with Ctrl/Cmd + Plus', () => {
    const initialZoom = camera.zoom

    // Simulate Ctrl/Cmd + Plus
    const event = new KeyboardEvent('keydown', {
      key: '+',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    expect(camera.zoom).toBeGreaterThan(initialZoom)
    expect(mockOnZoom).toHaveBeenCalled()
  })

  test('should zoom in with Ctrl/Cmd + Equals', () => {
    const initialZoom = camera.zoom

    // Simulate Ctrl/Cmd + Equals (common key for plus)
    const event = new KeyboardEvent('keydown', {
      key: '=',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    expect(camera.zoom).toBeGreaterThan(initialZoom)
    expect(mockOnZoom).toHaveBeenCalled()
  })

  test('should zoom out with Ctrl/Cmd + Minus', () => {
    camera.zoom = 2 // Start with higher zoom
    const initialZoom = camera.zoom

    // Simulate Ctrl/Cmd + Minus
    const event = new KeyboardEvent('keydown', {
      key: '-',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    expect(camera.zoom).toBeLessThan(initialZoom)
    expect(mockOnZoom).toHaveBeenCalled()
  })

  test('should work with metaKey (Cmd on Mac)', () => {
    const initialZoom = camera.zoom

    // Simulate Cmd + Plus on Mac
    const event = new KeyboardEvent('keydown', {
      key: '+',
      metaKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    expect(camera.zoom).toBeGreaterThan(initialZoom)
    expect(mockOnZoom).toHaveBeenCalled()
  })

  test('should respect zoom limits (0.1 to 20)', () => {
    // Test zoom out limit
    camera.zoom = 0.1
    const event = new KeyboardEvent('keydown', {
      key: '-',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)
    expect(camera.zoom).toBe(0.1) // Should not go below 0.1

    // Test zoom in limit
    camera.zoom = 20
    const zoomInEvent = new KeyboardEvent('keydown', {
      key: '+',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(zoomInEvent)
    expect(camera.zoom).toBe(20) // Should not go above 20
  })

  test('should center zoom on pointer when pointer is on canvas', () => {
    // Set pointer position
    pointer.x = 400
    pointer.y = 300
    
    const initialCameraX = camera.x
    const initialCameraY = camera.y

    const event = new KeyboardEvent('keydown', {
      key: '+',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    // Camera position should change to maintain pointer as zoom center
    expect(camera.x).not.toBe(initialCameraX)
    expect(camera.y).not.toBe(initialCameraY)
  })

  test('should center zoom on canvas center when pointer is outside', () => {
    // Set pointer outside canvas
    pointer.x = -1 // OUTSIDE_CANVAS value
    pointer.y = -1
    
    const event = new KeyboardEvent('keydown', {
      key: '+',
      ctrlKey: true,
      bubbles: true
    })
    document.body.dispatchEvent(event)

    // Should still zoom (onZoom should be called)
    expect(mockOnZoom).toHaveBeenCalled()
  })

  test('should prevent default behavior to avoid browser zoom', () => {
    const event = new KeyboardEvent('keydown', {
      key: '+',
      ctrlKey: true,
      bubbles: true
    })
    
    const preventDefaultSpy = jest.spyOn(event, 'preventDefault')
    document.body.dispatchEvent(event)

    expect(preventDefaultSpy).toHaveBeenCalled()
  })
})