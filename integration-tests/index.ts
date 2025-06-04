
import initCreator from "../src/index"

let new_asset_id = 1000

async function test() {
  const canvas = document.querySelector<HTMLCanvasElement>("canvas")!
  const creator = await initCreator(canvas)

  const fileInput = document.querySelector<HTMLInputElement>('input')!
  fileInput.addEventListener('change', (event) => {
    const { files } = (event.target as HTMLInputElement)
    if (!files) return

    const img = new Image()
    img.src = URL.createObjectURL(files[0])
    img.onload = () => {
      creator.addImage(new_asset_id, img)
      new_asset_id++
    }
  })
}

test()
