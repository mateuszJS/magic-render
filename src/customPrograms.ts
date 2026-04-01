import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/device'
import { Asset, CustomProgramError, Effect } from 'types'
import drawShapeShaderBase from 'WebGPU/programs/drawShape/base.wgsl'

interface CustomProgram {
  code: string
  callback: ReturnType<typeof getDrawShape>
  errors: CustomProgramError[]
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
let altProgramOnErr: ReturnType<typeof getDrawShape> | null
let programIdCounter: number
let updateSnapshot: VoidFunction = () => {}
let onProgramUpdate: (programId: number) => void = () => {}

export function init(
  newOnProgramUpdate: typeof onProgramUpdate,
  newUpdateSnapshot: typeof updateSnapshot
): void {
  customPrograms = new Map<number, CustomProgram>()
  altProgramOnErr = null
  programIdCounter = 0
  onProgramUpdate = newOnProgramUpdate
  updateSnapshot = newUpdateSnapshot
}

function getAlternativeProgramOnError() {
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
    false,
    (info) => {
      const errors = info.messages.filter((msg) => msg.type === 'error')
      if (errors.length > 0) {
        program.errors = errors.map<CustomProgramError>((err) => ({
          length: err.length,
          lineNum: err.lineNum - BEFORE_CUSTOM_PROGRAM_CODE_LINES,
          linePos: err.linePos,
          message: err.message,
          offset: err.offset - CUSTOM_PROGRAM_STRING_OFFSET,
        }))
        updateSnapshot()
      } else {
        program.callback = compiledProgramCb
        onProgramUpdate(newId)
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

function getEffectWithError(effect: Effect): Effect {
  if ('program' in effect.fill && typeof effect.fill.program.id === 'number') {
    const program = getCustomProgram(effect.fill.program.id)
    return {
      ...effect,
      fill: {
        ...effect.fill,
        program: {
          ...effect.fill.program,
          errors: program.errors,
        },
      },
    }
  }
  return effect
}

export function getAssetsWithError(assets: Asset[]) {
  return assets.map<Asset>((asset) =>
    'props' in asset
      ? {
          ...asset,
          effects: asset.effects.map(getEffectWithError),
        }
      : asset
  )
}

export function getAssetIdsByProgramId(assets: Asset[], programId: number): number[] {
  return assets
    .filter((asset) => {
      if ('props' in asset) {
        return asset.effects.some(
          (effect) => 'program' in effect.fill && effect.fill.program.id === programId
        )
      }
      return false
    })
    .map(
      (asset) =>
        asset.id ||
        (() => {
          throw Error('Asset id is missing')
        })()
    )
}
