export default function assertUnreachable(x: never): never {
  throw new Error(`Unreachable code executed with value: ${JSON.stringify(x)}`)
}
