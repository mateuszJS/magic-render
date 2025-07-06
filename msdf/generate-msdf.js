import generateBMFont from 'msdf-bmfont-xml'
import { SVGIcons2SVGFontStream } from 'svgicons2svgfont'
import fs from 'fs'
import svg2ttf from 'svg2ttf'
import { dirname } from 'path'
import { fileURLToPath } from 'url'
import path from 'path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

if (!fs.existsSync(getPath('output'))) {
  fs.mkdirSync(getPath('output'))
}

function getPath(pathname) {
  return path.resolve(__dirname, pathname)
}

const fontStream = new SVGIcons2SVGFontStream({
  fontName: 'icons',
})

fontStream
  .pipe(fs.createWriteStream(getPath('output/icons.svg')))
  .on('finish', function () {
    const ttf = svg2ttf(fs.readFileSync(getPath('output/icons.svg'), 'utf8'), {})
    fs.writeFileSync(getPath('output/icons.ttf'), ttf.buffer)

    generateBMFont(
      getPath('output/icons.ttf'),
      {
        outputType: 'json',
        charset: [String.fromCharCode(0xe001), String.fromCharCode(0xe002)],
      },
      (error, textures, font) => {
        if (error) throw error
        textures.forEach((texture, index) => {
          fs.writeFile(texture.filename + '.png', texture.texture, (err) => {
            if (err) throw err
          })
        })
        fs.writeFile(font.filename, font.data, (err) => {
          if (err) throw err
        })
      }
    )
  })
  .on('error', function (err) {
    console.log(err)
  })

const rotateIcon = fs.createReadStream(getPath('icons/rotate.svg'))
rotateIcon.metadata = {
  unicode: ['\uE001'],
  name: 'rotate',
}
fontStream.write(rotateIcon)

const trashIcon = fs.createReadStream(getPath('icons/trash-bin.svg'))
trashIcon.metadata = {
  unicode: ['\uE002'],
  name: 'trash-bin',
}
fontStream.write(trashIcon)

fontStream.end()
