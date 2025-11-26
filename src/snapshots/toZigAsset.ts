import { Asset, ZigAsset } from 'types'
import { toZigShapeProps } from './convert'
import { NO_ASSET_ID } from 'consts'
import * as Textures from 'textures'
import * as Fonts from 'fonts'

export default function toZigAsset(asset: Asset): ZigAsset {
  if ('paths' in asset) {
    // it's a shape
    return {
      shape: {
        id: asset.id || NO_ASSET_ID,
        paths: asset.paths,
        props: toZigShapeProps(asset.props),
        bounds: asset.bounds,
        sdf_texture_id: asset.sdf_texture_id || Textures.createSDF(),
        cache_texture_id: asset.cache_texture_id || null,
      },
    }
  } else if ('content' in asset) {
    const fontId = asset.typo_props.font_family_id
    Fonts.loadFont(fontId)

    return {
      text: {
        id: asset.id || NO_ASSET_ID,
        content: asset.content,
        bounds: asset.bounds,
        typo_props: asset.typo_props,
        props: toZigShapeProps(asset.props),
        sdf_texture_id: asset.sdf_texture_id,
      },
    }
  }
  // otherwise it's an image

  if (asset.bounds) {
    return {
      img: {
        id: asset.id || NO_ASSET_ID,
        bounds: asset.bounds,
        texture_id: asset.texture_id || Textures.add(asset.url), // if we got points, so we have url on the server for sure
      },
    }
  }

  console.error(asset)
  throw Error('unknwon asset scenario')
}
