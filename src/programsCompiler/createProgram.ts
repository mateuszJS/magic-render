import { CodeSnippet, ProgramCompilationInfo } from 'types'
import getDrawShape from 'WebGPU/programs/drawShape/getProgram'
import * as Uniforms from './uniforms'
import { CustomProgram } from 'programsCompiler/programs'
import * as PreviewTrigger from '../previewTrigger'
import { device, presentationFormat } from 'WebGPU/setupDevice'
import * as Logic from '../logic/index.zig'
import { extractInputNamesFromCode } from './extractInputNamesFromCode'

export function mergeCode(codeSnippets: CodeSnippet[]) {
  const orderedInputNames: string[] = []
  const mergedCode = codeSnippets.reduce((acc, snippet) => {
    const inputNames = extractInputNamesFromCode(snippet.content)
    const indexedSnippet = inputNames.reduce((acc, inputName) => {
      orderedInputNames.push(`${inputName}_${snippet.id}`)
      return acc.replaceAll(inputName, `${inputName}_${snippet.id}`)
    }, snippet.content)

    // example of a shader code snippet:
    // let fill = c_Color_<program_index>(s);
    // let progress = t_progress_<program_index>(s);
    // let dist = d_distance_<program_index>(s);
    // color = vec4f(fill.rgb, fill.a * progress * dist);

    const scopedSnippet = `
{
var color = vec4f(1.0, 1.0, 1.0, 1.0);
${indexedSnippet}
color = vec4f(color.rgb * color.a, color.a);
_priv_X821b6_total_color = mix(_priv_X821b6_total_color, color, color.a);
}
`
    return acc + '\n' + scopedSnippet
  }, '')

  return {
    mergedCode,
    orderedInputNames,
  }
}

export function createProgram(codeSnippets: CodeSnippet[], newId: number): CustomProgram {
  const { mergedCode, orderedInputNames } = mergeCode(codeSnippets)
  const uniformCode = Uniforms.getDeclarationCode(orderedInputNames)
  const { drawBuffer } = Uniforms.getBuffers(orderedInputNames, {}) // it will use only default values

  const program: CustomProgram = {
    codeSnippets,
    mergedCode,
    orderedInputNames,
    compilationInfo: [],
    execute: null,
    defaultDrawBuffer: drawBuffer,
  }

  PreviewTrigger.updateResourcesFlag('program-load-start')

  const customFunctions = Uniforms.getFunctionCode(orderedInputNames)

  const executeCallback = getDrawShape(
    device,
    presentationFormat,
    mergedCode,
    uniformCode,
    customFunctions,
    false,
    (info, offset, lines) => {
      Logic.invalidateCacheByProgramId(newId)

      const messages = info.messages.filter(
        (msg): msg is Omit<GPUCompilationMessage, 'type'> & { type: 'error' | 'warning' } =>
          msg.type === 'error' || msg.type === 'warning'
      )

      if (messages.length > 0) {
        program.compilationInfo = messages.map<ProgramCompilationInfo>((err) => ({
          length: err.length,
          lineNum: err.lineNum - lines,
          linePos: err.linePos,
          message: err.message,
          offset: err.offset - offset,
          type: err.type,
        }))

        console.log(`===========FAILED COMPILATION FOR PROGRAM ID: ${newId}==========`)
        console.log(messages)
        console.log('---codeSnippet---', mergedCode)
        console.log('---uniformCode---', uniformCode)
        console.log('---customFunctions---', customFunctions)
      }

      const isError = messages.some((msg) => msg.type === 'error')
      if (!isError) {
        program.execute = executeCallback
      }

      PreviewTrigger.updateResourcesFlag('program-load-end')
    }
  )

  return program
}
