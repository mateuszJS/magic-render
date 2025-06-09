import initCreator from '../src/index'
import SampleImg from './image-sample.png'

let new_asset_id = 1001

const params = new URLSearchParams(document.location.search)
const isSampleParam = params.has('sample') // is the string "Jonathan"

async function test() {
  const canvas = document.querySelector<HTMLCanvasElement>('canvas')!
  const creator = await initCreator(
    canvas,
    isSampleParam
      ? [
          {
            id: 1000,
            points: [
              { x: 84.5, y: 71.5, u: 0, v: 0 },
              { x: 688.5, y: 71.5, u: 1, v: 0 },
              { x: 688.5, y: 675.5, u: 1, v: 1 },
              { x: 84.5, y: 675.5, u: 0, v: 1 },
            ],
            url: SampleImg,
          },
        ]
      : [],
    console.log
  )

  const fileInput = document.querySelector<HTMLInputElement>('input')!
  fileInput.addEventListener('change', (event) => {
    const { files } = event.target as HTMLInputElement
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
