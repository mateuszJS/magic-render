import * as Logic from 'logic/index.zig'

const SOFT_BREAK_MARKER = '\u2060' // Word Joiner - stops navigation but invisible

let textarea: HTMLTextAreaElement | null = null

export function isEnabled(): boolean {
  return textarea !== null
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

function onInput(this: HTMLTextAreaElement) {
  const result = Logic.updateTextContent(this.value, this.selectionStart, this.selectionEnd)
  this.value = result.content
  updateSelection(result.selection_start, result.selection_end)
}

function onSelect(this: HTMLTextAreaElement) {
  skipSoftBreakMarkers(this.value, this, 'selectionStart')
  skipSoftBreakMarkers(this.value, this, 'selectionEnd')
  Logic.setCaretPosition(this.selectionStart, this.selectionEnd)
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

    newEl.addEventListener('input', onInput)
    newEl.addEventListener('selectionchange', onSelect)

    textarea = newEl
  }

  textarea.focus()
  updateContent(text)
}

export function disable(): void {
  if (textarea) {
    textarea.blur()
    document.body.removeChild(textarea)
  }
}
