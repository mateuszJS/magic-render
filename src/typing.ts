import * as Logic from 'logic/index.zig'

let textarea: HTMLTextAreaElement | null = null

export function isEnabled(): boolean {
  return textarea !== null
}

export function enable(): void {
  const newEl = document.createElement('textarea')
  newEl.style.position = 'fixed'
  newEl.style.left = '-200px'
  newEl.style.opacity = '0'
  document.body.appendChild(newEl)

  newEl.addEventListener('input', () => {
    Logic.updateTextContent(newEl.value)
  })

  newEl.addEventListener('selectionchange', () => {
    Logic.setCaretPosition(newEl.selectionStart, newEl.selectionEnd)
    console.log(newEl.selectionStart, newEl.selectionEnd)
  })

  newEl.focus()
  textarea = newEl
}

export function disable(): void {
  if (!textarea) throw Error('Not typing')

  textarea.blur()
  document.body.removeChild(textarea)
}
