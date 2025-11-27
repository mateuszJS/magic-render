import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/device'
import { Asset, CustomProgramError, SdfEffect } from 'types'

interface CustomProgram {
  code: string
  callback: ReturnType<typeof getDrawShape>
  errors: CustomProgramError[]
}

/* we assume that one code is associated with one id, if code changes,
id has to be updated as well. The callback does not have to represent actual code.
Callback holds last/aletnative successfully compiled code.
Old, unused id should be cleaned up at
some point in the future(e.g. during setSnapshot) */
let customPrograms: Map<number, CustomProgram>
let altProgramOnErr: ReturnType<typeof getDrawShape> | null
let programIdCounter: number
let updateSnapshot: VoidFunction = () => {}
let invalidateCache: (programId: number) => void = () => {}

export function init(
  newInvalidateCache: typeof invalidateCache,
  newUpdateSnapshot: typeof updateSnapshot
): void {
  customPrograms = new Map<number, CustomProgram>()
  altProgramOnErr = null
  programIdCounter = 0
  invalidateCache = newInvalidateCache
  updateSnapshot = newUpdateSnapshot
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
        setTimeout(() => {
          program.errors = errors
          updateSnapshot()
        }, 100)
      } else {
        program.callback = compiledProgramCb
        invalidateCache(newId)
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

function getEffectWithError(effect: SdfEffect): SdfEffect {
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
          props: {
            ...asset.props,
            sdf_effects: asset.props.sdf_effects.map(getEffectWithError),
          },
        }
      : asset
  )
}

export function getAssetIdsByProgramId(assets: Asset[], programId: number): number[] {
  return assets
    .filter((asset) => {
      if ('props' in asset) {
        return [...asset.props.sdf_effects].some(
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
