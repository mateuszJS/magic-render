import initCreator from '../src/index'
import SampleImg from './image-sample.png'

const params = new URLSearchParams(document.location.search)
const isSampleParam = params.has('sample') // is the string "Jonathan"

async function test() {
  const canvas = document.querySelector<HTMLCanvasElement>('canvas')!
  const creator = await initCreator(
    canvas,
    isSampleParam
      ? [
          {
            points: [
              {
                u: 0,
                v: 1,
                x: 106.5999984741211,
                y: 693.9000244140625,
              },
              {
                u: 1,
                v: 1,
                x: 723.4000244140625,
                y: 693.9000244140625,
              },
              {
                u: 1,
                v: 0,
                x: 723.4000244140625,
                y: 77.0999984741211,
              },
              {
                u: 0,
                v: 0,
                x: 106.5999984741211,
                y: 77.0999984741211,
              },
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
      creator.addImage(img)
    }
  })
}

test()
