import * as Logic from 'logic/index.zig'

const SOFT_BREAK_MARKER = '\u2060' // Word Joiner - stops navigation but invisible

let textarea: HTMLTextAreaElement | null = null

export function isEnabled(): boolean {
  return textarea !== null
}

function cleanText(text: string): string {
  // Remove all instances of SOFT_BREAK_MARKER followed by \n
  return text.replace(new RegExp(SOFT_BREAK_MARKER + '\n', 'g'), '')
}

function skipSoftBreakMarkers(
  text: string,
  el: HTMLTextAreaElement,
  field: 'selectionStart' | 'selectionEnd'
): void {
  if (text[el[field]] === '\n' && text[el[field] - 1] === SOFT_BREAK_MARKER) {
    el[field] = el[field] + 2
  }

  if (text[el[field] - 1] === '\n' && text[el[field] - 2] === SOFT_BREAK_MARKER) {
    el[field] = el[field] - 2
  }
}

export function update(text: string): void {
  if (!textarea) throw Error('Not typing')
  // console.log('UPDATE')
  textarea.value = text
}

export function enable(): void {
  const newEl = document.createElement('textarea')
  newEl.style.position = 'fixed'
  // newEl.style.left = '-9999px'
  // newEl.style.opacity = '0'
  newEl.style.width = '9999px'
  newEl.style.whiteSpace = 'pre-line'
  document.body.appendChild(newEl)

  newEl.addEventListener('input', () => {
    const cleanedText = cleanText(newEl.value)
    Logic.updateTextContent(cleanedText)
  })

  newEl.addEventListener('selectionchange', () => {
    skipSoftBreakMarkers(newEl.value, newEl, 'selectionStart')
    skipSoftBreakMarkers(newEl.value, newEl, 'selectionEnd')

    const beforeStart =
      newEl.value
        .slice(0, newEl.selectionStart)
        .split('')
        .filter((c) => c === SOFT_BREAK_MARKER).length * 2

    const beforeEnd =
      newEl.value
        .slice(0, newEl.selectionEnd)
        .split('')
        .filter((c) => c === SOFT_BREAK_MARKER).length * 2

    Logic.setCaretPosition(newEl.selectionStart - beforeStart, newEl.selectionEnd - beforeEnd)
  })

  newEl.focus()
  textarea = newEl
}

export function disable(): void {
  if (!textarea) throw Error('Not typing')

  textarea.blur()
  document.body.removeChild(textarea)
}
