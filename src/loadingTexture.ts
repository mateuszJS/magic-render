export default function getLoadingTexture(
  device: GPUDevice,
  presentationFormat: GPUTextureFormat
): GPUTexture {
  const textureWidth = 5
  const textureHeight = 7
  const _ = [255, 0, 0, 255] // red
  const y = [255, 255, 0, 255] // yellow
  const b = [0, 0, 255, 255] // blue
  // prettier-ignore
  const textureData = new Uint8Array([
    b, _, _, _, _,
    _, y, y, y, _,
    _, y, _, _, _,
    _, y, y, _, _,
    _, y, _, _, _,
    _, y, _, _, _,
    _, _, _, _, _,
  ].flat())

  const texture = device.createTexture({
    label: 'yellow F on red',
    size: [textureWidth, textureHeight],
    format: presentationFormat,
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  })
  device.queue.writeTexture(
    { texture },
    textureData,
    { bytesPerRow: textureWidth * 4 },
    { width: textureWidth, height: textureHeight }
  )

  return texture
}
