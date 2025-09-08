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

export const canvasMatrix: {
  buffer: GPUBuffer
} = { buffer: null as unknown as GPUBuffer } // should throw error when used before assigning
export let pickCanvasMatrixBuffer: GPUBuffer

let buffersToDestroy: Array<GPUBuffer | GPUTexture> = []

export function delayedDestroy(gpuObject: GPUBuffer | GPUTexture) {
  buffersToDestroy.push(gpuObject)
}

export function destroyGpuObjects() {
  buffersToDestroy.forEach((buffer) => buffer.destroy())
  buffersToDestroy = []
}

export default function initPrograms(device: GPUDevice, presentationFormat: GPUTextureFormat) {
  canvasMatrix.buffer = device.createBuffer({
    label: 'uniforms',
    size: 16 /*projection matrix*/ * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  pickCanvasMatrixBuffer = device.createBuffer({
    label: 'uniforms',
    size: 16 /*projection matrix*/ * 4,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  })

  drawTriangle = getDrawTriangle(device, presentationFormat)
  drawBezier = getDrawBezier(device, presentationFormat)
  draw3dModelTexture = getDraw3dModelTexture(device, presentationFormat)
  draw3dModel = getDraw3dModel(device, presentationFormat)
  draw3dModelLight = getDraw3dModelLight(device, presentationFormat)
  drawBlur = getBlur(device, presentationFormat)
  drawTexture = getDrawtexture(device, presentationFormat)
  pickTexture = getPickTexture(device, pickCanvasMatrixBuffer)
  pickTriangle = getPickTriangle(device, pickCanvasMatrixBuffer)
  drawMSDF = getDrawMSDF(device, presentationFormat)
  drawSolidShape = getDrawShape(
    device,
    presentationFormat,
    solidFS,
    1 /*dist_start*/ + 1 /*dist_end*/ + 2 /*padding*/ + 4 /*color*/
  )
  drawLinearGradientShape = getDrawShape(
    device,
    presentationFormat,
    linearGradientFS,
    1 /*dist_start*/ +
      1 /*dist_end*/ +
      1 /*stops counts*/ +
      1 /*padding*/ +
      2 /*start*/ +
      2 /*end*/ +
      (4 /*color*/ + 1 /*offset*/ + 3) /*padding*/ * 10 /*stops*/
  )
  drawRadialGradientShape = getDrawShape(
    device,
    presentationFormat,
    radialGradientFS,
    1 /*dist_start*/ +
      1 /*dist_end*/ +
      1 /*stops_count*/ +
      1 /*radius_ratio*/ +
      2 /*start*/ +
      2 /*end*/ +
      (4 /*color*/ + 1 /*offset*/ + 3) /*padding*/ * 10 /*stops*/
  )
  pickShape = getPickShape(device, pickCanvasMatrixBuffer)
  computeShape = getComputeShape(device)
}
