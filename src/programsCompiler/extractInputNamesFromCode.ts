import { INPUT_TYPES } from './uniforms'

const prefixes = Object.keys(INPUT_TYPES)
const regex = new RegExp(
  `(?<![a-zA-Z0-9_.])([${prefixes.join('')}]_[a-zA-Z0-9_]+)\\s*\\(\\s*s\\s*\\)`,
  'g'
)
// (?<![a-zA-Z0-9_.]) - string is not preceed by valid variable names or reads
// ([adc]_ — capture group starting with exactly one of a, d, or c, followed by _
// [a-zA-Z0-9_]+) — rest of the variable name (one or more valid identifier chars)

export function extractInputNamesFromCode(code: string): string[] {
  // prettier-ignore
  return Array.from(
    new Set(
      [...code.matchAll(regex)].map((m) => m[1])
    )
  )
}
