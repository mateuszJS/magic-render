import { ElementNode, Node } from 'svg-parser'
import { getProps } from './utils'

type DefStop = {
  offset: number
  color: [number, number, number, number]
}

// TypeScript doesn't have negative types
// so it's a way around to use this instea of
// Except<string, 'paths' | 'stops' | 'id', | 'href'>
export type AttrValue = string | number | undefined

export type Def = {
  paths?: Point[][]
  stops?: DefStop[]
  href?: string
  id?: string
  type?: 'linear-gradient' | 'radial-gradient'
  gradientTransform?: number[]
  x1?: AttrValue
  y1?: AttrValue
  x2?: AttrValue
  y2?: AttrValue
  'stop-color'?: AttrValue
  'stop-opacity'?: AttrValue
  offset?: AttrValue
  cx?: AttrValue
  cy?: AttrValue
  r?: AttrValue
  rx?: AttrValue
  ry?: AttrValue
  x?: AttrValue
  y?: AttrValue
  width?: AttrValue
  height?: AttrValue
  transform?: AttrValue
  fill?: AttrValue
  stroke?: AttrValue
}

export type Defs = Record<string, Def>

export function resolveAll(defs: Defs): void {
  const keys = Object.keys(defs)
  for (const id of keys) {
    const d = defs[id]
    // Ensure any href chains are resolved and memoized back into defs
    const resolved = resolveRef(defs, d)
    defs[id] = resolved
  }
}

// Merge referenced gradient (href) into current. Current overrides referenced.
function resolveRef(defs: Defs, def: Def, seen = new Set<string>()): Def {
  if (!def.href) return def // the end of chain

  const id = String(def.href).replace('#', '')
  if (seen.has(id)) {
    // Circular reference detected
    return def
  }
  seen.add(id)

  const base = defs[id]
  if (!base) return def

  const resolvedBase = resolveRef(defs, base, seen)
  def = { ...resolvedBase, ...def }
  def.href = undefined
  if (def.id) {
    defs[def.id] = def // Memoize
  }
  return def
}

export function collect(node: Node, defs: Defs, insideDefs = false): void {
  if (!('children' in node)) return

  node.children.forEach((child) => {
    if (typeof child === 'string') return

    const props = getProps(child as unknown as ElementNode)

    switch ((child as ElementNode).tagName) {
      case 'linearGradient': {
        if (!props.id) return
        defs[props.id] = {
          type: 'linear-gradient',
          ...props,
        }
        return
      }
      case 'radialGradient': {
        if (!props.id) return
        defs[props.id] = {
          type: 'radial-gradient',
          ...props,
        }
        return
      }
      case 'path': {
        if (insideDefs) {
          if (!props.id) return
          defs[props.id] = props
        }
        return
      }
      case 'defs': {
        insideDefs = true
        break
      }
    }
    collect(child, defs, insideDefs)
  })
}
