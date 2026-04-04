import { device } from 'WebGPU/device'
import * as Textures from 'textures'
import { computeShape } from 'WebGPU/programs/initPrograms'

type WorkerResult = {
  pixels: ArrayBuffer
  width: number
  height: number
  bytesPerRow: number
  id: number
}

// add flag | GPUTextureUsage.COPY_DST, to textures

export function createComputeShapeWorker(triggerRedraw: VoidFunction) {
  const worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' })
  let workerFailed = false

  worker.onerror = (e) => {
    console.error('[computeShape worker] failed, falling back to main-thread compute:', e)
    workerFailed = true
  }

  worker.onmessage = (e: MessageEvent<WorkerResult>) => {
    const { pixels, width, height, bytesPerRow, id } = e.data
    const texture = Textures.getTexture(id)
    // skip if texture was resized again before result arrived
    if (texture.width !== width || texture.height !== height) {
      console.warn('[computeShape worker] texture size mismatch, discarding result', {
        expected: { width, height },
        actual: { width: texture.width, height: texture.height },
      })
      return
    }
    device.queue.writeTexture({ texture }, pixels, { bytesPerRow }, [width, height])
    triggerRedraw()
  }

  return {
    compute(curvesDataView: DataView<ArrayBuffer>, width: number, height: number, id: number) {
      if (workerFailed) {
        // fallback: run on main thread with its own encoder
        const enc = device.createCommandEncoder({ label: 'computeShape fallback' })
        const pass = enc.beginComputePass()
        computeShape(pass, curvesDataView, Textures.getTexture(id))
        pass.end()
        device.queue.submit([enc.finish()])
        triggerRedraw()
        return
      }

      // slice to get a plain transferable ArrayBuffer (DataView may point into WASM memory)
      const curvesData = curvesDataView.buffer.slice(
        curvesDataView.byteOffset,
        curvesDataView.byteOffset + curvesDataView.byteLength
      )
      worker.postMessage({ curvesData, width, height, id }, [curvesData])
    },
  }
}
