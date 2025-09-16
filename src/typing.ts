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

/* ensures the selection is not behind a soft break OR enter which follows soft break */
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
  textarea.value = text
}

export function enable(text: string): void {
  const newEl = document.createElement('textarea')
  newEl.style.position = 'fixed'
  // newEl.style.left = '-9999px'
  // newEl.style.opacity = '0'
  newEl.style.width = '9999px'
  newEl.style.whiteSpace = 'pre-line'
  newEl.value = text
  document.body.appendChild(newEl)

  newEl.addEventListener('input', () => {
    const cleanedText = cleanText(newEl.value)
    // in Logic we are goign to reapply all soft breaks in correct places
    Logic.updateTextContent(cleanedText)
  })

  newEl.addEventListener('selectionchange', () => {
    skipSoftBreakMarkers(newEl.value, newEl, 'selectionStart')
    skipSoftBreakMarkers(newEl.value, newEl, 'selectionEnd')

    Logic.setCaretPosition(newEl.selectionStart, newEl.selectionEnd)
  })

  newEl.focus()
  textarea = newEl
}

export function disable(): void {
  if (!textarea) throw Error('Not typing')

  textarea.blur()
  document.body.removeChild(textarea)
}
