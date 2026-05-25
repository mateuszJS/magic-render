export function areSoftVecEqual(a: Array<null | number>, b: Array<null | number>) {
  if (a.length !== b.length) return false
  return a.every((val, i) => {
    if (val === null || b[i] === null) return val === null && b[i] === null
    return Math.abs(val - b[i]) <= Number.EPSILON
  })
}
