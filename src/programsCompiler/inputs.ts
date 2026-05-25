import { ProgramInputs } from 'types'
import { areSoftVecEqual } from 'utils/areSoftVecEqual'
import * as Logic from '../logic/index.zig'
import { extractInputNamesFromCode } from './extractInputNamesFromCode'
import * as PredefinedPrograms from './predefinedPrograms'
import * as Uniforms from './uniforms'

type Entry = {
  props: ProgramInputs['props']
  drawBuffer: Float32Array<ArrayBuffer>
  pickBuffer: Float32Array<ArrayBuffer> /* [sdf tex scale, maxDistance, minDistance] */
}
let inputsCache: Map<number, Entry>
let inputsIdCounter: number

export function init(): void {
  inputsCache = new Map([
    [
      Logic.HIGHLIGHT_PATH_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.HIGHLIGHT_PATH), {
        c_Color: [0, 0, 1, 1],
        d_distance: [null, +Logic.SKELETON_LINE_WIDTH / 2, -Logic.SKELETON_LINE_WIDTH / 2, null],
      }),
    ],
    [
      Logic.TRANSFORM_UI_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.SOLID_COLOR), {
        d_distance: [null, null, 0, null],
        c_Color: [1, 1, 1, 1],
      }),
    ],
    [
      Logic.TRANSFORM_UI_HOVER_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.SOLID_COLOR), {
        d_distance: [null, null, 0, null],
        c_Color: [0, 0, 0, 1],
      }),
    ],
    [
      Logic.DEFAULT_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.SOLID_COLOR), {
        d_distance: [null, null, 0, null],
        c_Color: [0.5, 1, 0.5, 1],
      }),
    ],
    [
      Logic.COMPILING_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.SOLID_COLOR), {
        d_distance: [null, null, 0, null],
        c_Color: [0, 0, 0, 1],
      }),
    ],
    [
      Logic.ERROR_INPUTS_ID,
      Uniforms.getBuffers(extractInputNamesFromCode(PredefinedPrograms.ERROR), {
        d_distance: [null, null, 0, null],
      }),
    ],
  ])
  inputsIdCounter = Math.max(...Array.from(inputsCache.keys())) + 1 // be one bigger than predefiend programs biggest id
}

// On first snapshot, there is no programId assigned yet
export function getSerializationInfo(
  programInputsId: number | undefined,
  selectedValues: ProgramInputs['props'],
  code: string
): { program_inputs_id: number; padding: number } {
  if (programInputsId) {
    const cacheInputs = inputsCache.get(programInputsId)
    if (cacheInputs) {
      let isSame = true

      // Snapshots.updateProgramInputs(programId, inputs)

      for (const [key, values] of Object.entries(cacheInputs.props)) {
        const currValue = selectedValues[key]
        if (!currValue || areSoftVecEqual(currValue, values)) {
          isSame = false
          break
        }
      }

      if (isSame) {
        return {
          program_inputs_id: programInputsId,
          padding: cacheInputs.pickBuffer[2] * -1,
        }
      }
    }
    // TODO: think about removing, we cannot do it right away because it might be used next frame still
    // we should probably "schedule" program for deletion
  }

  const newId = inputsIdCounter++

  const orderedInputNames = extractInputNamesFromCode(code)
  const { props, drawBuffer, pickBuffer } = Uniforms.getBuffers(orderedInputNames, selectedValues)

  inputsCache.set(newId, {
    props,
    drawBuffer,
    pickBuffer,
  })

  return {
    program_inputs_id: newId,
    padding: pickBuffer[2] * -1,
  }
}

export function getInputs(programInputsId: number) {
  const inputs = inputsCache.get(programInputsId)
  if (!inputs) throw Error('Unknown program inputs id: ' + programInputsId)
  return inputs
}
