import { CustomProgramError } from 'types'
import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import * as Uniforms from './uniforms'
import { CustomProgram } from 'programsCompiler/programs'
import * as PreviewTrigger from '../previewTrigger'
import drawShapeShaderBase from 'WebGPU/programs/drawShape/base.wgsl'
import customProgramWrapper from 'WebGPU/programs/drawShape/custom-program-wrapper.wgsl'
import { device, presentationFormat } from 'WebGPU/setupDevice'
import * as Logic from '../logic/index.zig'
import { extractInputNamesFromCode } from './extractInputNamesFromCode'

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

export function createProgram(codeSnippet: string, newId: number): CustomProgram {
  const orderedInputNames = extractInputNamesFromCode(codeSnippet)
  const uniformCode = Uniforms.getDeclarationCode(orderedInputNames)
  const { drawBuffer } = Uniforms.getBuffers(orderedInputNames, {}) // it will use only default values

  const program: CustomProgram = {
    code: codeSnippet,
    errors: [],
    execute: null,
    defaultDrawBuffer: drawBuffer,
  }

  PreviewTrigger.updateResourcesFlag('program-load-start')

  const customFunctions = Uniforms.getFunctionCode(orderedInputNames)

  const code =
    customProgramWrapper.replace(CUSTOM_CODE_PLACEHOLDER, codeSnippet) + '\n' + customFunctions

  const executeCallback = getDrawShape(
    device,
    presentationFormat,
    code,
    uniformCode,
    false,
    (info) => {
      Logic.invalidateCacheByProgramId(newId)
      const errors = info.messages.filter((msg) => msg.type === 'error')

      if (errors.length > 0) {
        program.errors = errors.map<CustomProgramError>((err) => ({
          length: err.length,
          lineNum: err.lineNum - BEFORE_CUSTOM_PROGRAM_CODE_LINES,
          linePos: err.linePos,
          message: err.message,
          offset: err.offset - CUSTOM_PROGRAM_STRING_OFFSET,
        }))
        console.log(`===========FAILED COMPILATION FOR PROGRAM ID: ${newId}==========`)
        console.log(errors)
        console.log(code)
        console.log('---uniformCode---', uniformCode)
        console.log('---customFunctions---', customFunctions)
      } else {
        program.execute = executeCallback
      }

      PreviewTrigger.updateResourcesFlag('program-load-end')
    }
  )

  return program
}
