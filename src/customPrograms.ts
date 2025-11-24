import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/device'

interface CustomProgram {
  code: string
  callback: ReturnType<typeof getDrawShape>
}

const customPrograms = new Map<number, CustomProgram>()

function createProgram(code: string): CustomProgram {
  const callback = getDrawShape(
    device,
    presentationFormat,
    code.replace('${CUSTOM_PROGRAM_CODE}', customProgramWrapper),
    0
  )

  return { code, callback }
}

export function getCustomProgramId(programCode: string): number {
  for (const [id, program] of customPrograms) {
    if (program.code === programCode) {
      return id
    }
  }

  const newId = customPrograms.size
  customPrograms.set(newId, createProgram(programCode))
  return newId
}

export function getCustomProgram(programId: number): CustomProgram {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)
  return program
}
