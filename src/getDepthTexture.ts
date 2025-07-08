let depthTexture: GPUTexture | undefined

export default function getDepthTexture(device: GPUDevice, width: number, height: number) {
  if (!depthTexture || depthTexture.width !== width || depthTexture.height !== height) {
    depthTexture?.destroy()
    depthTexture = device.createTexture({
      size: [width, height],
      format: 'depth24plus',
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    })
  }

  return depthTexture
}
