import getMultisampleTexture from './getMultisampleTexture'
import getDepthTexture from './getDepthTexture'

export default function getCanvasRenderDescriptor(context: GPUCanvasContext, device: GPUDevice) {
  // here we need to render that texture into canvas
  const canvasTexture = context.getCurrentTexture()

  const depthTexture = getDepthTexture(device, canvasTexture.width, canvasTexture.height)
  const multisampleTexture = getMultisampleTexture(
    device,
    canvasTexture.width,
    canvasTexture.height,
    canvasTexture.format
  )
  const descriptor: GPURenderPassDescriptor = {
    // describe which textures we want to raw to and how use them
    label: 'our render to canvas renderPass',
    colorAttachments: [
      {
        view: multisampleTexture.createView(),
        resolveTarget: canvasTexture.createView(), // resolveTarget is used to resolve multisample texture into single sample texture
        clearValue: [0, 0, 0, 1],
        loadOp: 'clear', // before rendering clear the texture to value "clear". Other option is "load" to load existing content of the texture into GPU so we can draw over it
        storeOp: 'store', // to store the result of what we draw, other option is "discard"
      },
    ],
    // depthStencilAttachment: {
    //   view: depthTexture.createView(), // placholder to calm down TS
    //   depthClearValue: 1.0,
    //   depthLoadOp: 'clear',
    //   depthStoreOp: 'discard',
    // },
  }

  return descriptor
}
