import { PointUV, BasicProps, TypoProps, Program, ProgramInputs } from 'types'
import * as CustomPrograms from 'programsCompiler/programs'
import * as CustomProgramInputs from 'programsCompiler/inputs'

export function toBounds(bounds: PointUV[]): PointUV[] {
  return bounds.map((point) => ({
    x: point.x,
    y: point.y,
    u: point.u,
    v: point.v,
  }))
}

export function toZigProps(props: BasicProps): BasicProps {
  return {
    opacity: props.opacity,
    blur:
      props.blur && (props.blur.x > Number.EPSILON || props.blur.y > Number.EPSILON)
        ? props.blur
        : null,
  }
}

// BasicProps are shared between API & Zig
export function toBasicProps(props: BasicProps): BasicProps {
  return {
    blur: props.blur
      ? {
          x: props.blur.x,
          y: props.blur.y,
        }
      : null,
    opacity: props.opacity,
  }
}

export function toProgram(program_id: number): Program {
  const program = CustomPrograms.getAssetDetails(program_id)

  return {
    id: program_id,
    codeSnippets: program.codeSnippets,
    compilationInfo: program.compilationInfo,
  }
}

export function toProgramInputs(program_inputs_id: number): ProgramInputs {
  const inputs = CustomProgramInputs.getInputs(program_inputs_id)

  return {
    id: program_inputs_id,
    props: inputs.props,
  }
}

export function toTypoProps(props: TypoProps): TypoProps {
  return {
    font_size: props.font_size,
    font_family_id: props.font_family_id,
    line_height: props.line_height,
    is_sdf_shared: props.is_sdf_shared,
  }
}
