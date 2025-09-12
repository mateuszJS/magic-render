import * as Logic from 'logic/index.zig'

let input: HTMLTextAreaElement | null = null

export function isEnabled(): boolean {
  return input !== null
}

export function enable(): void {
  console.log('ENAVBLE TYPING')
  const newInput = document.createElement('textarea')
  newInput.style.position = 'fixed'
  newInput.style.left = '-200px'
  newInput.style.opacity = '0'
  document.body.appendChild(newInput)

  newInput.addEventListener('input', () => {
    Logic.updateTextContent(newInput.value)
  })

  newInput.focus()
  input = newInput
}

export function disable(): void {
  if (!input) throw Error('Not typing')

  input.blur()
  document.body.removeChild(input)
}
