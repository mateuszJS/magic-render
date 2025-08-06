const TestShapeSvg = `
<svg viewBox="0 0 100 100" version="1.1" xmlns="http://www.w3.org/2000/svg">
    <path d="M86.467,29.511C82.472,23.734 73.515,15.84 65.626,11.626C53.545,5.174 39.264,3.83 32.01,10.728C19.493,22.63 48.138,36.888 12.048,58.79C-9.698,71.987 26.544,106.787 62.514,97.022C98.483,87.256 99.853,48.867 86.467,29.511Z"/>
</svg>
`
function testSvgToSegments(): number[] {
  const testCanvas = document.createElement('canvas')
  testCanvas.style.position = 'absolute'
  document.body.appendChild(testCanvas)
  testCanvas.width = testCanvas.clientWidth
  testCanvas.height = testCanvas.clientHeight

  const segments = svgToSegments(TestShapeSvg)

  const ctx = testCanvas.getContext('2d')!

  segments.forEach(({ points: [start, cp1, cp2, end] }, i) => {
    ctx.strokeStyle = `hsl(${Math.round((i / segments.length) * 120)}, 100%, 50%)`
    ctx.lineWidth = 10
    ctx.beginPath()
    ctx.moveTo(start.x, start.y)
    ctx.bezierCurveTo(
      cp1.x,
      cp1.y,
      (cp2 as Point).x,
      (cp2 as Point).y,
      (end as Point).x,
      (end as Point).y
    )
    ctx.stroke()
  })

  return segments.flatMap((segment) => [
    ...segment.points.flatMap((point) => [point.x, testCanvas.height - point.y]),
    segment.length,
    0, // just a padding to make it vec2f
  ])
}
