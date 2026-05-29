import { Asset, ProjectSnapshot, ZigProjectSnapshot } from 'types'
import { toBounds, toBasicProps, toTypoProps, toProgram, toProgramInputs } from './convert'
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
        props: toBasicProps(shape.props),
        program: toProgram(shape.program_id),
        inputs: toProgramInputs(shape.program_inputs_id),
        sdf_texture_id: shape.sdf_texture_id,
        cache_texture_id: shape.cache_texture_id,
      }
    } else if ('text' in asset && asset.text) {
      return {
        id: asset.text.id,
        content: Typing.sanitizeContent(asset.text.content),
        bounds: toBounds([...asset.text.bounds]),
        typo_props: toTypoProps(asset.text.typo_props),
        props: toBasicProps(asset.text.props),
        program: toProgram(asset.text.program_id),
        inputs: toProgramInputs(asset.text.program_inputs_id),
        sdf_texture_id: asset.text.sdf_texture_id,
        is_sdf_shared: asset.text.is_sdf_shared,
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

// The functions below could be replaced by just trigerring a new snapshot from zig, BUT
// it doesn't seem right to produce a snapshot even thoug hfro mZig poitn fo view, nothing has changed
// thos changeS(program inputs, image url) only exist in JS
export function updateImageUrl(oldUrl: string, newUrl: string) {
  const newAssets = lastSnapshot.assets.map<Asset>((asset) => {
    if ('url' in asset && asset.url === oldUrl) {
      return {
        ...asset,
        url: newUrl,
      }
    }
    return asset
  })
  lastSnapshot.assets = newAssets
}
