import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/setupDevice'
import { CustomProgramError } from 'types'
import drawShapeShaderBase from 'WebGPU/programs/drawShape/base.wgsl'
import * as Logic from './logic/index.zig'

interface CustomProgram {
  code: string
  errors: CustomProgramError[]
  execute: ReturnType<typeof getDrawShape> | null
}

const CUSTOM_CODE_PLACEHOLDER = '${CUSTOM_PROGRAM_CODE}'
const CUSTOM_CODE_TOTAL_BASE = drawShapeShaderBase + customProgramWrapper

const CUSTOM_PROGRAM_STRING_OFFSET = CUSTOM_CODE_TOTAL_BASE.indexOf(CUSTOM_CODE_PLACEHOLDER)
if (CUSTOM_PROGRAM_STRING_OFFSET === -1) {
  throw Error(
    `string: "${CUSTOM_CODE_PLACEHOLDER}" was not found in custom progrma template: ${CUSTOM_CODE_TOTAL_BASE}`
  )
}

const BEFORE_CUSTOM_PROGRAM_CODE = CUSTOM_CODE_TOTAL_BASE.slice(0, CUSTOM_PROGRAM_STRING_OFFSET)
const BEFORE_CUSTOM_PROGRAM_CODE_LINES = BEFORE_CUSTOM_PROGRAM_CODE.split('\n').length - 1

/* we assume that one code is associated with one id, if code changes,
id has to be updated as well. The callback does not have to represent actual code.
Callback holds last/alternative successfully compiled code.
Old, unused id should be cleaned up at
some point in the future(e.g. during setSnapshot) */
let customPrograms: Map<number, CustomProgram>
let placeholderProgram: ReturnType<typeof getDrawShape> | null
let altProgramOnErr: ReturnType<typeof getDrawShape> | null
let programIdCounter: number

export function init(): void {
  customPrograms = new Map<number, CustomProgram>()
  placeholderProgram = null
  altProgramOnErr = null
  programIdCounter = 0
}

function getPlaceholderProgram() {
  if (!placeholderProgram) {
    placeholderProgram = getDrawShape(
      device,
      presentationFormat,
      customProgramWrapper.replace(CUSTOM_CODE_PLACEHOLDER, 'color=vec4f(0);'),
      4 * 4,
      false,
      (info) => {
        console.warn('Alternative program compilation info:', info)
      }
    )
  }

  return placeholderProgram
}

function getFailedProgram() {
  if (!altProgramOnErr) {
    altProgramOnErr = getDrawShape(
      device,
      presentationFormat,
      customProgramWrapper.replace(
        CUSTOM_CODE_PLACEHOLDER,
        'let s=20.0;let p=floor(uv*s);let c=(p.x+p.y)%2.0;color=vec4f(c,c,c,1);'
      ),
      4 * 4,
      false,
      (info) => {
        console.warn('Alternative program compilation info:', info)
      }
    )
  }
  return altProgramOnErr
}

function createProgram(code: string, newId: number): CustomProgram {
  const program: CustomProgram = {
    code,
    errors: [],
    execute: null,
  }

  const executeCallback = getDrawShape(
    device,
    presentationFormat,
    customProgramWrapper.replace('${CUSTOM_PROGRAM_CODE}', code),
    4 * 4,
    false,
    (info) => {
      Logic.invalidateCacheByProgram(newId)
      const errors = info.messages.filter((msg) => msg.type === 'error')

      if (errors.length > 0) {
        program.errors = errors.map<CustomProgramError>((err) => ({
          length: err.length,
          lineNum: err.lineNum - BEFORE_CUSTOM_PROGRAM_CODE_LINES,
          linePos: err.linePos,
          message: err.message,
          offset: err.offset - CUSTOM_PROGRAM_STRING_OFFSET,
        }))
      } else {
        program.execute = executeCallback
      }
    }
  )

  return program
}

// On first snapshot, there is no programId assigned yet
export function getProgramId(programId: number | undefined, code: string): number {
  if (programId) {
    const program = customPrograms.get(programId)
    if (program && program.code === code) {
      // program is still good
      return programId
    }
    // TODO: think about removing, we cannot do it right away because it might be used next frame still
    // we should probably "schedule" program for deletion
  }

  const newId = programIdCounter++
  customPrograms.set(newId, createProgram(code, newId))
  return newId
}

export function getCodeData(programId: number): CustomProgram {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)
  return program
}

export function getExecutable(programId: number): ReturnType<typeof getDrawShape> {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)

  if (program.execute === null) {
    return program.errors.length > 0 ? getFailedProgram() : getPlaceholderProgram()
  }

  return program.execute
}
