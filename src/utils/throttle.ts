const noArgs = Symbol('no args')

// It's a throttle with tail call support
export default function throttle<T extends (...args: never[]) => void>(
  func: T,
  limit: number
): (...args: Parameters<T>) => void {
  let inThrottle: boolean
  let lastArgs: Parameters<T> | typeof noArgs = noArgs

  return function trigger(this: ThisParameterType<T>, ...args: Parameters<T>) {
    if (!inThrottle) {
      func.apply(this, args)
      inThrottle = true
      setTimeout(() => {
        inThrottle = false
        if (lastArgs !== noArgs) {
          trigger.apply(this, lastArgs)
          lastArgs = noArgs
        }
      }, limit)
    } else {
      lastArgs = args
    }
  }
}
