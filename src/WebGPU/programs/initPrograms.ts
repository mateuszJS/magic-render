import getDrawTriangle from './drawTriangle/getProgram'
import getDrawBezier from './drawBezier/getProgram'
import getDraw3dModelTexture from './draw3dModelTexture/getProgram'
import getDraw3dModel from './draw3dModel/getProgram'
import getDraw3dModelLight from './draw3dModelLight/getProgram'
import getBlur from './blur/getProgram'
import getDrawtexture from './drawTexture/getProgram'
import getPickTexture from './pickTexture/getProgram'
import getPickTriangle from './pickTriangle/getProgram'
import getDrawMSDF from './drawMSDF/getProgram'
import getDrawShape from './drawShape/getProgram'

export let drawTriangle: ReturnType<typeof getDrawTriangle>
export let drawBezier: ReturnType<typeof getDrawBezier>
export let draw3dModel: ReturnType<typeof getDraw3dModel>
export let draw3dModelTexture: ReturnType<typeof getDraw3dModelTexture>
export let draw3dModelLight: ReturnType<typeof getDraw3dModelLight>
export let drawBlur: ReturnType<typeof getBlur>
export let drawTexture: ReturnType<typeof getDrawtexture>
export let pickTexture: ReturnType<typeof getPickTexture>
export let pickTriangle: ReturnType<typeof getPickTriangle>
export let drawMSDF: ReturnType<typeof getDrawMSDF>
export let drawShape: ReturnType<typeof getDrawShape>

export let canvasMatrixBuffer: GPUBuffer
export let pickCanvasMatrixBuffer: GPUBuffer

export default function initPrograms(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  canvasMatrixBuffer = device.createBuffer({
    label: 'uniforms',
    size: 16 /*projection matrix*/ * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  pickCanvasMatrixBuffer = device.createBuffer({
    label: 'uniforms',
    size: 16 /*projection matrix*/ * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  const buffersToDestroy: GPUBuffer[] = []

  drawTriangle = getDrawTriangle(device, presentationFormat, canvasMatrixBuffer, buffersToDestroy)
  drawBezier = getDrawBezier(device, presentationFormat)
  draw3dModelTexture = getDraw3dModelTexture(device, presentationFormat)
  draw3dModel = getDraw3dModel(device, presentationFormat)
  draw3dModelLight = getDraw3dModelLight(device, presentationFormat)
  drawBlur = getBlur(device)
  drawTexture = getDrawtexture(device, presentationFormat, canvasMatrixBuffer)
  pickTexture = getPickTexture(device, pickCanvasMatrixBuffer)
  pickTriangle = getPickTriangle(device, pickCanvasMatrixBuffer)
  drawMSDF = getDrawMSDF(device, presentationFormat, canvasMatrixBuffer)
  drawShape = getDrawShape(device, presentationFormat, canvasMatrixBuffer, buffersToDestroy)

  return function cleanup() {
    buffersToDestroy.forEach((buffer) => buffer.destroy())
  }
}
