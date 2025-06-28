import getDrawTriangle from './drawTriangle/getProgram'
import getDrawBezier from './drawBezier/getProgram'
import getDraw3dModelTexture from './draw3dModelTexture/getProgram'
import getDraw3dModel from './draw3dModel/getProgram'
import getDraw3dModelLight from './draw3dModelLight/getProgram'
import getBlur from './blur/getProgram'
import getDrawtexture from './drawTexture/getProgram'
import getPickTexture from './pickTexture/getProgram'
import getPickTriangle from './pickTriangle/getProgram'
import getGenerateMSDF from './generateMSDF/getProgram'

export let drawTriangle: ReturnType<typeof getDrawTriangle>
export let drawBezier: ReturnType<typeof getDrawBezier>
export let draw3dModel: ReturnType<typeof getDraw3dModel>
export let draw3dModelTexture: ReturnType<typeof getDraw3dModelTexture>
export let draw3dModelLight: ReturnType<typeof getDraw3dModelLight>
export let drawBlur: ReturnType<typeof getBlur>
export let drawTexture: ReturnType<typeof getDrawtexture>
export let pickTexture: ReturnType<typeof getPickTexture>
export let pickTriangle: ReturnType<typeof getPickTriangle>
export let generateMSDF: ReturnType<typeof getGenerateMSDF>

export default function initPrograms(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  drawTriangle = getDrawTriangle(device, presentationFormat)
  drawBezier = getDrawBezier(device, presentationFormat)
  draw3dModelTexture = getDraw3dModelTexture(device, presentationFormat)
  draw3dModel = getDraw3dModel(device, presentationFormat)
  draw3dModelLight = getDraw3dModelLight(device, presentationFormat)
  drawBlur = getBlur(device)
  drawTexture = getDrawtexture(device, presentationFormat)
  pickTexture = getPickTexture(device)
  pickTriangle = getPickTriangle(device)
  generateMSDF = getGenerateMSDF(device, presentationFormat)
}
