import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/device'
import { CustomProgramError } from 'types'

interface CustomProgram {
  code: string
  callback: ReturnType<typeof getDrawShape>
  errors: CustomProgramError[]
}

/* we assume that one code is assosiated with an id, if code changes,
id has to be updated as well. Old, unused id should be cleaned up at
some point in the future(e.g. during setSnapshot) */
let customPrograms: Map<number, CustomProgram>
let altProgramOnErr: ReturnType<typeof getDrawShape> | null
let programIdCounter: number

export function init(): void {
  customPrograms = new Map<number, CustomProgram>()
  altProgramOnErr = null
  programIdCounter = 0
}

let triggerSnapshotsUpdate: (programId: number) => void = () => {}
export function setTriggerSnapshotsUpdateCallback(callback: typeof triggerSnapshotsUpdate): void {
  triggerSnapshotsUpdate = callback
}

function getAlternativeProgramOnError() {
  if (!altProgramOnErr) {
    altProgramOnErr = getDrawShape(
      device,
      presentationFormat,
      customProgramWrapper.replace(
        '${CUSTOM_PROGRAM_CODE}',
        'let s=20.0;let p=floor(uv*s);let c=(p.x+p.y)%2.0;color=vec4f(c,c,c,1);'
      ),
      4 * 4,
      (info) => {
        console.warn('Alternative program compilation info:', info)
      }
    )
  }
  return altProgramOnErr
}

function createProgram(
  code: string,
  newId: number,
  placeholderProgramCb: ReturnType<typeof getDrawShape>
): CustomProgram {
  const program: CustomProgram = {
    code,
    callback: placeholderProgramCb,
    errors: [],
  }

  const compiledProgramCb = getDrawShape(
    device,
    presentationFormat,
    customProgramWrapper.replace('${CUSTOM_PROGRAM_CODE}', code),
    4 * 4,
    (info) => {
      const errors = info.messages.filter((msg) => msg.type === 'error')
      if (errors.length > 0) {
        program.errors = errors
      } else {
        program.callback = compiledProgramCb
        triggerSnapshotsUpdate(newId)
      }
    }
  )
  return program
}

export function getCustomProgramId(id: number | undefined, code: string): number {
  let placeholderProgramCb = getAlternativeProgramOnError()

  if (typeof id === 'number') {
    const program = customPrograms.get(id)
    if (program) {
      if (program.code === code) {
        return id // cached program is still valid
      } else {
        placeholderProgramCb = program.callback
        customPrograms.delete(id) // outdated cache
      }
    }
  }

  const newId = programIdCounter++
  customPrograms.set(newId, createProgram(code, newId, placeholderProgramCb))
  return newId
}

export function getCustomProgram(programId: number): CustomProgram {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)
  return program
}
