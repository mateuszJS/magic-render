export let device: GPUDevice
export let presentationFormat: GPUTextureFormat
export let storageFormat: GPUTextureFormat

export default async function setup() {
  if (!navigator.gpu) {
    throw Error('this browser does not support WebGPU')
  }

  const adapter = await navigator.gpu.requestAdapter()

  if (!adapter) {
    throw Error('this browser supports webgpu but it appears disabled')
  }
  const hasBGRA8unormStorage = adapter.features.has('bgra8unorm-storage')

  device = await adapter.requestDevice({
    requiredFeatures: hasBGRA8unormStorage ? ['bgra8unorm-storage'] : [],
    // to debug with GPU query : ['timestamp-query'],
    label: 'id: ' + Date.now(),
  })

  device.lost.then((info) => {
    console.error(`WebGPU device was lost: ${info.message}`)

    if (info.reason !== 'destroyed') {
      // reprot issue to the tracking system
      // getDevice(callback);
    }
  })

  presentationFormat = navigator.gpu.getPreferredCanvasFormat()
  storageFormat = hasBGRA8unormStorage ? navigator.gpu.getPreferredCanvasFormat() : 'rgba8unorm'
}
