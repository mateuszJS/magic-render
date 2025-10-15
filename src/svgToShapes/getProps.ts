import { Node, ElementNode } from 'svg-parser'
import { Def } from './definitions'
import parseEllipse from './parseEllipse'
import parsePathData from './parsePathData'
import parseRect from './parseRect'
import { getNum, isElementNode, parseColor, parseTransform } from './utils'
import { Color } from 'types'

export default function getProps(node: ElementNode): Def {
  let rawProps = node.properties
  if (typeof node.properties?.style === 'string') {
    const styleProps = {} as Record<string, string | number>
    node.properties.style.split(';').forEach((declaration) => {
      const [property, value] = declaration.split(':')
      if (property && value) {
        styleProps[property.trim()] = value.trim()
      }
    })
    // Direct properties override style properties
    rawProps = { ...styleProps, ...node.properties }
  }

  if (!rawProps) return {}

  const def: Def = { ...rawProps }

  switch (node.tagName) {
    case 'path': {
      def.paths = parsePathData(rawProps.d as string)
      delete def.d
      break
    }
    case 'rect': {
      def.paths = [
        parseRect(
          getNum(rawProps.x),
          getNum(rawProps.y),
          getNum(rawProps.width, 1),
          getNum(rawProps.height, 1)
        ),
      ]
      delete def.x
      delete def.y
      delete def.width
      delete def.height
      break
    }
    case 'ellipse': {
      def.paths = [
        parseEllipse(
          getNum(rawProps.cx),
          getNum(rawProps.cy),
          getNum(rawProps.rx),
          getNum(rawProps.ry)
        ),
      ]
      delete def.cx
      delete def.cy
      delete def.rx
      delete def.ry
      break
    }
    case 'circle': {
      def.paths = [
        parseEllipse(
          getNum(rawProps.cx),
          getNum(rawProps.cy),
          getNum(rawProps.r),
          getNum(rawProps.r)
        ),
      ]
      delete def.cx
      delete def.cy
      delete def.r
      break
    }
    case 'radialGradient':
    case 'linearGradient': {
      if (node.children.length > 0) {
        def.stops = getGradientStops(node.children)
      }
      break
    }
    case 'filter': {
      if (isElementNode(node.children[0])) {
        addFilterProps(def, node.children[0])
      }
      break
    }
  }

  if ('gradientTransform' in rawProps) {
    def.gradientTransform = parseTransform(String(rawProps.gradientTransform))
  }

  return def
}

function getGradientStops(nodes: Array<string | Node>) {
  return nodes.map((stop) => {
    if (!isElementNode(stop)) {
      return { offset: 0, color: [0, 0, 0, 0] as Color }
    }
    const stopProps = getProps(stop)
    const color = parseColor(String(stopProps['stop-color'] ?? '#000'))
    color[3] = getNum(stopProps['stop-opacity'], 1)

    return {
      offset: Number(stopProps.offset ?? 0),
      color,
    }
  })
}

function addFilterProps(def: Def, child: ElementNode) {
  if (child.tagName === 'feGaussianBlur') {
    def.type = 'gaussian-blur'

    const v = child.properties?.stdDeviation
    let sx = 0
    let sy = 0
    if (typeof v === 'number') {
      sx = v
      sy = v
    } else if (typeof v === 'string') {
      const parts = v.trim().split(/[ ,]+/).filter(Boolean)
      if (parts.length >= 2) {
        sx = getNum(parts[0], 0)
        sy = getNum(parts[1], 0)
      } else if (parts.length === 1) {
        sx = getNum(parts[0], 0)
        sy = sx
      }
    }
    def.stdDeviation = [sx, sy]
  }
}
