import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/device'

interface CustomProgram {
  code: string
  callback: ReturnType<typeof getDrawShape>
}

const customPrograms = new Map<number, CustomProgram>()

let compilationErrorCallback: (info: GPUCompilationInfo) => void = () => {}
export function setCallbackCompilationError(callback: (info: GPUCompilationInfo) => void): void {
  compilationErrorCallback = callback
}

let altProgramOnErr: ReturnType<typeof getDrawShape> | null = null
function getAlternativeProgramOnError() {
  if (!altProgramOnErr) {
    altProgramOnErr = getDrawShape(
      device,
      presentationFormat,
      customProgramWrapper.replace(
        '${CUSTOM_PROGRAM_CODE}',
        'let s=20.0;let p=floor(uv*s);let c=(p.x+p.y)%2.0;color=vec4f(c,c,c,1);'
      ),
      4 * 4
    )
  }
  return altProgramOnErr
}

function createProgram(code: string): CustomProgram {
  const result = {
    code,
    callback: (() => {}) as ReturnType<typeof getDrawShape>,
  }

  result.callback = getDrawShape(
    device,
    presentationFormat,
    customProgramWrapper.replace('${CUSTOM_PROGRAM_CODE}', code),
    4 * 4,
    (info) => {
      if (info.messages.some((msg) => msg.type === 'error')) {
        result.callback = getAlternativeProgramOnError()
        compilationErrorCallback(info)
      }
    }
  )
  return result
}

let programIdCounter = 0
export function getCustomProgramId(id: number | undefined, code: string): number {
  if (typeof id === 'number') {
    const program = customPrograms.get(id)
    if (program && program.code === code) {
      return id
    }
  }

  const newId = programIdCounter++
  customPrograms.set(newId, createProgram(code))
  return newId
}

export function getCustomProgram(programId: number): CustomProgram {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)
  return program
}
