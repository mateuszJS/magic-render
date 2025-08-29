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
import solidFS from './drawShape/solid.wgsl'
import linearGradientFS from './drawShape/linear-gradient.wgsl'
import radialGradientFS from './drawShape/radial-gradient.wgsl'
import getPickShape from './pickShape/getProgram'
import getComputeShape from './computeShape/getProgram'

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
export let drawSolidShape: ReturnType<typeof getDrawShape>
export let drawLinearGradientShape: ReturnType<typeof getDrawShape>
export let drawRadialGradientShape: ReturnType<typeof getDrawShape>
export let pickShape: ReturnType<typeof getPickShape>
export let computeShape: ReturnType<typeof getComputeShape>

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
  drawSolidShape = getDrawShape(
    device,
    presentationFormat,
    canvasMatrixBuffer,
    buffersToDestroy,
    solidFS,
    1 /*stroke width*/ + 4 /*stroke color*/ + 4 /*fill color*/ + /*padding*/ 3
  )
  drawLinearGradientShape = getDrawShape(
    device,
    presentationFormat,
    canvasMatrixBuffer,
    buffersToDestroy,
    linearGradientFS,
    4 /*stroke width*/ +
      4 /*stops counts*/ +
      8 /*padding*/ +
      4 * 10 /*stops positions*/ +
      4 * 10 /*stops colors*/
  )
  drawRadialGradientShape = getDrawShape(
    device,
    presentationFormat,
    canvasMatrixBuffer,
    buffersToDestroy,
    radialGradientFS,
    1 /*stroke width*/ + 4 /*stroke color*/ + 4 /*fill color*/ + /*padding*/ 3
  )
  pickShape = getPickShape(device, pickCanvasMatrixBuffer, buffersToDestroy)
  computeShape = getComputeShape(device, buffersToDestroy)

  return function cleanup() {
    buffersToDestroy.forEach((buffer) => buffer.destroy())
  }
}
