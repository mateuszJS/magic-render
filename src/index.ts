import canvasSizeObserver from 'WebGPU/canvasSizeObserver'
import getDevice from 'WebGPU/getDevice'
import initPrograms from 'WebGPU/programs/initPrograms'
import runCreator from 'run'
import { createTextureFromSource } from 'WebGPU/getTexture'
import { init_state, add_texture, connectOnAssetUpdateCallback } from './logic/index.zig'
import initMouseController from 'WebGPU/pointer'
import getDefaultPoints from 'utils/getDefaultPoints'

export type SerializedAsset = Omit<AssetZig, 'texture_id'> & {
  url: string
}

export interface CreatorAPI {
  addImage: (img: HTMLImageElement, points?: PointUV[]) => void
  destroy: VoidFunction
}

export interface TextureSource {
  url: string
  texture: GPUTexture
}

export default async function initCreator(
  canvas: HTMLCanvasElement,
  assets: SerializedAsset[],
  onAssetsUpdate: (assets: SerializedAsset[]) => void
): Promise<CreatorAPI> {
  /* setup WebGPU stuff */
  const device = await getDevice()

  // setTimeout(() => {
  //   const url = new URL(document.location.href)
  //   // const params = new URLSearchParams(url.search)
  //   const isRedirectParam = url.searchParams.has('redirect') // is the string "Jonathan"
  //   if (isRedirectParam) {
  //     url.searchParams.delete('redirect')
  //     window.history.pushState({}, '', url)
  //     setTimeout(() => {
  //       url.pathname = '/non-existing-path-just-for-testing-bf-cache-and-wasm'
  //       window.history.pushState({}, '', url)
  //     }, 1000)
  //   }
  // }, 1000)

  init_state(canvas.clientWidth, canvas.clientHeight)
  const context = canvas.getContext('webgpu')
  if (!context) throw Error('WebGPU from canvas needs to be always provided')

  const presentationFormat = navigator.gpu.getPreferredCanvasFormat()
  context.configure({
    device,
    format: presentationFormat,
    // Specify we want both RENDER_ATTACHMENT and COPY_SRC since we
    // will copy out of the swapchain texture.
  })

  canvasSizeObserver(canvas, device, () => {
    // state.needsRefresh = true
  })

  initPrograms(device, presentationFormat)

  initMouseController(canvas)

  const textures: TextureSource[] = []
  connectOnAssetUpdateCallback((serializedData: AssetZig[]) => {
    const serializedAssetsTextureUrl = [...serializedData].map<SerializedAsset>((asset) => ({
      points: [...asset.points].map((point) => ({
        x: point.x,
        y: point.y,
        u: point.u,
        v: point.v,
      })),
      url: textures[asset.texture_id].url,
    }))
    onAssetsUpdate(serializedAssetsTextureUrl)
  })

  function addImage(img: HTMLImageElement, points?: PointUV[]) {
    const newTextureId = textures.length
    textures.push({
      url: img.src,
      texture: createTextureFromSource(device, img, { flipY: true }),
    })

    add_texture(points || getDefaultPoints(img, canvas), newTextureId)
  }

  assets.forEach((asset) => {
    const img = new Image()
    img.src = asset.url
    img.onload = () => {
      addImage(img, asset.points)
    }
  })

  const stopCreator = runCreator(canvas, context, device, presentationFormat, textures)

  return {
    addImage,
    destroy: () => {
      console.log('Destroying device')
      stopCreator()
      context.unconfigure()
      device.destroy()
    },
  }
}
