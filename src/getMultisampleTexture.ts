export default function getMultisampleTexture(
  device: GPUDevice,
  width: number,
  height: number,
  format: GPUTextureFormat,
  texture?: GPUTexture
) {
  if (!texture || texture.width !== width || texture.height !== height) {
    texture?.destroy()
    texture = device.createTexture({
      label: 'multisample texture',
      format: format,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      size: [width, height],
      sampleCount: 4,
    })
  }

  return texture
}
