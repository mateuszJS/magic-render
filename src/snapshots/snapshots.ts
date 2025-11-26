import { Asset, ProjectSnapshot, ZigProjectSnapshot } from 'types'
import { toBounds, toShapeProps, toTypoProps } from './convert'
import * as Typing from 'typing'
import * as Textures from 'textures'

export let lastSnapshot: ProjectSnapshot
let snapshotWaitingCalls: Array<(snapshot: ProjectSnapshot) => void> | null // to delay calls until initial snapshot is ready

export function init(width: number, height: number) {
  lastSnapshot = {
    width,
    height,
    assets: [],
  }
  snapshotWaitingCalls = []
}

export function withSnapshotReady(cb: (snapshot: ProjectSnapshot) => void) {
  if (snapshotWaitingCalls) {
    snapshotWaitingCalls.push(cb)
  } else {
    cb(lastSnapshot)
  }
}

export function saveSnapshot(snapshot: ZigProjectSnapshot) {
  const assets = [...snapshot.assets].map<Asset>((asset) => {
    if ('img' in asset && asset.img) {
      const img = asset.img
      return {
        id: img.id,
        texture_id: img.texture_id,
        bounds: toBounds([...img.bounds]),
        url: Textures.getUrl(img.texture_id),
      }
    } else if ('shape' in asset && asset.shape) {
      const shape = asset.shape
      if (!shape.bounds) {
        throw Error('Shape bounds are missing in asset with id: ' + shape.id)
      }
      return {
        id: shape.id,
        paths: [...shape.paths].map((path) =>
          [...path].map((point) => ({
            x: point.x,
            y: point.y,
          }))
        ),
        bounds: toBounds([...shape.bounds]),
        props: toShapeProps(shape.props),
        sdf_texture_id: shape.sdf_texture_id,
        cache_texture_id: shape.cache_texture_id,
      }
    } else if ('text' in asset && asset.text) {
      return {
        id: asset.text.id,
        content: Typing.sanitizeContent(asset.text.content),
        bounds: toBounds([...asset.text.bounds]),
        typo_props: toTypoProps(asset.text.typo_props),
        props: toShapeProps(asset.text.props),
        sdf_texture_id: asset.text.sdf_texture_id,
      }
    } else {
      throw Error('Unknown asset type')
    }
  })

  lastSnapshot = {
    width: snapshot.width,
    height: snapshot.height,
    assets,
  }

  if (snapshotWaitingCalls) {
    snapshotWaitingCalls.forEach((cb) => cb(lastSnapshot))
    snapshotWaitingCalls = null
  }
}
