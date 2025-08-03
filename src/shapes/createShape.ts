import { Node } from 'svg-parser'
import * as Logic from 'logic/index.zig'
import parsePathData from './parsePathData'
import parseRect from './parseRect'
import type { PathSegment } from './types'
import parseColor from './parseColor'
import parseElipse from './parseEllipse'

export default function createShapes(node: Node, svgHeight: number): void {
  if (!('children' in node)) return

  node.children.forEach((child) => {
    if (typeof child !== 'string') {
      if ('properties' in child && typeof child.properties === 'object') {
        const props = child.properties
        const serializedProps: ShapeProps = {}
        if (props.fill) {
          const rgba = parseColor(props.fill as string)
          serializedProps.fill_color = rgba
        }
        let result: PathSegment[][] | undefined = undefined

        switch (child.tagName) {
          case 'path':
            if (typeof props?.d !== 'string') {
              throw Error("Path without 'd' property")
            }
            result = parsePathData(props.d, svgHeight)
            break
          case 'rect':
            if (typeof props?.width !== 'number' || typeof props?.height !== 'number') {
              throw Error("Path without 'd' property")
            }
            result = [parseRect(props.width, props.height, svgHeight)]
            break
          case 'ellipse':
            if (typeof props?.rx !== 'number' || typeof props?.ry !== 'number') {
              throw Error("Ellipse without 'rx' or 'ry' property")
            }
            if (typeof props?.cx !== 'number' || typeof props?.cy !== 'number') {
              throw Error("Ellipse without 'cx' or 'cy' property")
            }
            result = [parseElipse(props.cx, props.cy, props.rx, props.ry, svgHeight)]
        }

        if (result) {
          Logic.add_shape(result, serializedProps)
        }
      }
      createShapes(child, svgHeight)
    }
  })
}
