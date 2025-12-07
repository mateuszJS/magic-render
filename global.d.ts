export {}

declare global {
  type OneOf<T> = {
    [K in keyof T]: { [P in K]: T[P] } & { [P in Exclude<keyof T, K>]: null }
  }[keyof T]
}
