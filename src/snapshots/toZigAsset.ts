import { Asset, ZigAsset } from 'types'
import { toZigEffects, toZigProps } from './convert'
import { NO_ASSET_ID } from 'consts'
import * as Textures from 'textures'
import * as Fonts from 'fonts'

export default function toZigAsset(asset: Asset, captureError: (error: unknown) => void): ZigAsset {
  if ('paths' in asset) {
    // it's a shape
    return {
      shape: {
        id: asset.id || NO_ASSET_ID,
        paths: asset.paths,
        bounds: asset.bounds,
        props: toZigProps(asset.props),
        effects: toZigEffects(asset.effects),
        sdf_texture_id: asset.sdf_texture_id || Textures.createSDF(),
        cache_texture_id: asset.cache_texture_id || null,
      },
    }
  } else if ('content' in asset) {
    Fonts.loadFont(asset.typo_props.font_family_id)

    return {
      text: {
        id: asset.id || NO_ASSET_ID,
        content: asset.content,
        bounds: asset.bounds,
        typo_props: asset.typo_props,
        props: toZigProps(asset.props),
        effects: toZigEffects(asset.effects),
        sdf_texture_id: asset.sdf_texture_id ?? Textures.createSDF(),
        is_sdf_shared: asset.is_sdf_shared,
      },
    }
  }
  // otherwise it's an image

  if (asset.bounds) {
    return {
      img: {
        id: asset.id || NO_ASSET_ID,
        bounds: asset.bounds,
        texture_id: asset.texture_id || Textures.add(asset.url, captureError), // if we got points, so we have url on the server for sure
      },
    }
  }

  throw Error('Unknown asset: ' + asset)
}
