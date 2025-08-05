// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
export default function debounce(callback: Function, ms: number) {
  let timeoutId: number
  return (...args: unknown[]) => {
    window.clearTimeout(timeoutId)
    timeoutId = window.setTimeout(() => {
      callback(...args)
    }, ms)
  }
}
