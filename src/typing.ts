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

function isBetweenSoftBreakMarkers(text: string, position: number): boolean {
  return text[position - 1] === SOFT_BREAK_MARKER && text[position] === '\n'
}

function isRightAfterSoftBreakMarkers(text: string, position: number): boolean {
  return text[position - 2] === SOFT_BREAK_MARKER && text[position - 1] === '\n'
}

/* ensures the selection is not between a soft break and \n NOR after this pair of special characters  */
const previous = {
  selectionStart: 0,
  selectionEnd: 0,
}
function skipSoftBreakMarkers(
  text: string,
  el: HTMLTextAreaElement,
  field: 'selectionStart' | 'selectionEnd'
): void {
  if (isBetweenSoftBreakMarkers(text, el[field])) {
    const movedByOne = previous[field] == el[field] - 1
    el[field] = movedByOne ? el[field] + 2 : el[field] - 1
    // + 2 -> to jump over SOFT_BREAK_MARKER and \n
    // - 1 -> to come back to position before SOFT_BREAK_MARKER
  }

  if (isRightAfterSoftBreakMarkers(text, el[field])) {
    el[field] = el[field] - 2
  }

  previous[field] = el[field]
}

export function updateContent(text: string): void {
  if (!textarea) throw Error('Not typing')

  let start = textarea.selectionStart
  let end = textarea.selectionEnd

  textarea.value = text

  // Those two conditions ensures that selection won't endup between SOFT_BREAK_MARKER and \n
  if (isBetweenSoftBreakMarkers(text, start)) {
    start += 2
  }
  if (isBetweenSoftBreakMarkers(text, end)) {
    end += 2
  }

  textarea.selectionStart = start
  textarea.selectionEnd = end
}

export function updateSelection(start: number, end: number): void {
  if (!textarea) throw Error('Not typing')

  textarea.selectionStart = start
  textarea.selectionEnd = end
}

export function enable(text: string): void {
  if (!textarea) {
    const newEl = document.createElement('textarea')
    newEl.style.position = 'fixed'
    // newEl.style.left = '-9999px'
    // newEl.style.opacity = '0'
    newEl.style.width = '9999px'
    newEl.style.whiteSpace = 'pre-line'
    document.body.appendChild(newEl)

    newEl.addEventListener('input', () => {
      const cleanedText = cleanText(newEl.value)
      // in Logic we are going to re-apply all soft breaks in correct places
      Logic.updateTextContent(cleanedText)
    })

    newEl.addEventListener('selectionchange', () => {
      skipSoftBreakMarkers(newEl.value, newEl, 'selectionStart')
      skipSoftBreakMarkers(newEl.value, newEl, 'selectionEnd')

      Logic.setCaretPosition(newEl.selectionStart, newEl.selectionEnd)
    })

    textarea = newEl
  }

  textarea.focus()
  if (textarea.value !== text) {
    updateContent(text)
  }
}

export function disable(): void {
  if (!textarea) throw Error('Not typing')

  textarea.blur()
  document.body.removeChild(textarea)
}
