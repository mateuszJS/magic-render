import type getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import { CustomProgramError } from 'types'
import * as Logic from '../logic/index.zig'
import * as PredefinedPrograms from './predefinedPrograms'
import { createProgram } from './createProgram'

export interface CustomProgram {
  code: string
  errors: CustomProgramError[]
  execute: ReturnType<typeof getDrawShape> | null
  defaultDrawBuffer: Float32Array<ArrayBuffer>
}

/* we assume that one code is associated with one id, if code changes,
id has to be updated as well. The callback does not have to represent actual code.
Callback holds last/alternative successfully compiled code.
Old, unused id should be cleaned up at
some point in the future(e.g. during setSnapshot) */
let customPrograms: Map<number, CustomProgram>
let programIdCounter: number

export function init(): void {
  customPrograms = new Map<number, CustomProgram>([
    // TODO: we generate tons of EXACTLY SAME PROGRAMS, ITPS POINTLESS
    [
      Logic.HIGHLIGHT_PATH_PROGRAM_ID,
      createProgram(PredefinedPrograms.HIGHLIGHT_PATH, Logic.HIGHLIGHT_PATH_PROGRAM_ID),
    ],
    [
      Logic.SOLID_COLOR_PROGRAM_ID,
      createProgram(PredefinedPrograms.SOLID_COLOR, Logic.SOLID_COLOR_PROGRAM_ID),
    ],
    [Logic.ERROR_PROGRAM_ID, createProgram(PredefinedPrograms.ERROR, Logic.ERROR_PROGRAM_ID)],
  ])
  programIdCounter = Math.max(...Array.from(customPrograms.keys())) + 1 // be one bigger than predefiend programs biggest id
}

export type RenderData = {
  execute: ReturnType<typeof getDrawShape> | null
  uniform: Float32Array<ArrayBuffer>
}

// On first snapshot, there is no programId assigned yet
export function getSerializationInfo(
  programId: number | undefined,
  code: string
): number /* program id */ {
  // const compiledUniform = compileUniformSchema(inputs)

  if (programId) {
    const program = customPrograms.get(programId)
    if (program && program.code === code) {
      return programId
    }
    // TODO: think about removing, we cannot do it right away because it might be used next frame still
    // we should probably "schedule" program for deletion
  }

  const newId = programIdCounter++

  customPrograms.set(newId, createProgram(code, newId))
  return newId
}

export function getAssetDetails(programId: number): CustomProgram {
  const program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)
  return program
}

export function getProgram(programId: number) {
  let program = customPrograms.get(programId)
  if (!program) throw Error('Unknown program id: ' + programId)

  if (program.execute === null) {
    program = customPrograms.get(
      program.errors.length > 0 ? Logic.ERROR_PROGRAM_ID : Logic.SOLID_COLOR_PROGRAM_ID
    )
    if (!program) throw Error('Unknown DEFAULT program id: ' + programId)
  }

  return program
}
