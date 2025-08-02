let multisampleTexture: GPUTexture | undefined

export default function getMultisampleTexture(
  device: GPUDevice,
  width: number,
  height: number,
  format: GPUTextureFormat
) {
  if (
    !multisampleTexture ||
    multisampleTexture.width !== width ||
    multisampleTexture.height !== height
  ) {
    multisampleTexture?.destroy()
    multisampleTexture = device.createTexture({
      format: format,
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
      size: [width, height],
      sampleCount: 4,
    })
  }

  return multisampleTexture
}
