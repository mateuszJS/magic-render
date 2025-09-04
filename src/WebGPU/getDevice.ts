export default async function getDevice() {
  if (!navigator.gpu) {
    throw Error('this browser does not support WebGPU')
  }

  const adapter = await navigator.gpu.requestAdapter()

  if (!adapter) {
    throw Error('this browser supports webgpu but it appears disabled')
  }
  const hasBGRA8unormStorage = adapter.features.has('bgra8unorm-storage')

  const device = await adapter.requestDevice({
    requiredFeatures: hasBGRA8unormStorage ? ['bgra8unorm-storage'] : [],
  })
  device.lost.then((info) => {
    console.error(`WebGPU device was lost: ${info.message}`)

    if (info.reason !== 'destroyed') {
      // reprot issue to the tracking system
      // getDevice(callback);
    }
  })

  const presentationFormat = hasBGRA8unormStorage
    ? navigator.gpu.getPreferredCanvasFormat()
    : 'rgba8unorm'

  return { device, presentationFormat }
}
