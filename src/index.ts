import canvasSizeObserver from "WebGPU/canvasSizeObserver"
import getDevice from "WebGPU/getDevice"
import initPrograms from "WebGPU/programs/initPrograms"
import runCreator from "run"
import { createTextureFromSource } from 'WebGPU/getTexture'
import clamp from "utils/clamp"
import { Point } from "types"
import { State } from "../crate/glue_code"
import initMouseController from "WebGPU/pointer"

export interface CreatorAPI {
  addImage: (id: number, img: HTMLImageElement) => void
  updatePoints: (id: number, points: Point[]) => void
  destroy: VoidFunction
}

export default async function initCreator(
  canvas: HTMLCanvasElement,
): Promise<CreatorAPI> {
  /* setup WebGPU stuff */
  const device = await getDevice()

  const state = State.new(300, 300)

  const context = canvas.getContext("webgpu")
  if (!context) throw Error("WebGPU from canvas needs to be always provided")

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

  const textures: GPUTexture[] = []
  const assetsList: number[] = []
  runCreator(state, canvas, context, device, presentationFormat, textures, assetsList)

  // initUI(state)
  return {
    addImage: (id, img) => {
      const newTextureIndex = textures.length
      textures.push(createTextureFromSource(device, img))
      const scale = getDefaultTextureScale(img, canvas)
      const scaledWidth = img.width * scale
      const scaledHeight = img.height * scale
      const paddingX = (canvas.width - scaledWidth) * .5
      const paddingY = (canvas.height - scaledHeight) * .5
      state.add_texture(
        id,
        [
          { x: paddingX, y: paddingY, u: 0, v: 0 },
          { x: paddingX + scaledWidth, y: paddingY, u: 1, v: 0 },
          { x: paddingX + scaledWidth, y: paddingY + scaledHeight, u: 1, v: 1 },
          { x: paddingX, y: paddingY + scaledHeight, u: 0, v: 1 },
        ],
        newTextureIndex
      )
      assetsList.push(id)
    },
    updatePoints: (id, points) => {
      state.update_points(id, points)
    },
    destroy: () => {
      context.unconfigure()
      device.destroy()
    }
  }
}

/**
 * Returns visualy pleasant size of texture, to make sure it doesn't overflow canvas but also is not too small to manipulate
*/
function getDefaultTextureScale(img: HTMLImageElement, canvas: HTMLCanvasElement) {
  const heightDiff = canvas.height - img.height
  const widthDiff = canvas.width - img.width

  if (heightDiff < widthDiff) {
    const height = clamp(img.height, canvas.height * 0.2, canvas.height * 0.8)
    return height / img.height
  }

  const width = clamp(img.width, canvas.width * 0.2, canvas.width * 0.8)
  return width / img.width
}
