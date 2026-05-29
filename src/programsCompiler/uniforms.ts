import { ProgramInputs } from 'types'
import * as Logic from '../logic/index.zig'

export const INPUT_TYPES = {
  a: {
    uniformType: 'vec4f',
    defaultValue: [1.5, 2, 2.4, 2.9],
    getFn: (name: string) => `
      fn ${name}(s: Sample) -> f32 {
        let start_soft = u.${name}.x;
        let start = u.${name}.y;
        let end = u.${name}.z;
        let end_soft = u.${name}.w;

        // Normalize s.angle to [0, TAU) — handles -2PI..+2PI input
        let a = ((s.blend_angle % TAU) + TAU) % TAU;
        // let a = ((s.angle % TAU) + TAU) % TAU;

        // Shift into a local frame where start_soft lands at 0.
        // Everything past start_soft wraps cleanly; no seam in the band.
        // Double-mod ((x % TAU) + TAU) % TAU is required because WGSL's % is
        // fmod-style (sign follows dividend), so a single (x + TAU) % TAU
        // leaves a negative result whenever x < -TAU — which happens as soon
        // as start_soft crosses 0 while start/end are large negatives.
        let local_a        = (((a        - start_soft) % TAU) + TAU) % TAU;
        let local_start    = (((start    - start_soft) % TAU) + TAU) % TAU;
        let local_end      = (((end      - start_soft) % TAU) + TAU) % TAU;
        let local_end_soft = (((end_soft - start_soft) % TAU) + TAU) % TAU;
        // local_start_soft is implicitly 0.0

        let rise  = smoothstep(              -s.fw, local_start    + s.fw, local_a);
        let fall  = smoothstep(local_end - s.fw, local_end_soft + s.fw, local_a);
        return rise * (1.0 - fall);

      }
    `,
  },
  c: {
    uniformType: 'vec4f',
    defaultValue: [1, 1, 1, 1],
    getFn: (name: string) => `
      fn ${name}(s: Sample) -> vec4f {
        return u.${name};
      }
    `,
  },
  d: {
    uniformType: 'vec4f',
    defaultValue: [null, null, 0, null],
    getFn: (name: string) => `
      fn ${name}(s: Sample) -> f32 {
        let start_soft = u.${name}.x * u.texture_scale;
        let start = u.${name}.y * u.texture_scale;
        let end = u.${name}.z * u.texture_scale;
        let end_soft = u.${name}.w * u.texture_scale;

        let inner_alpha = smoothstep(start - s.fw, start_soft    + s.fw, s.signed_distance);
        let outer_alpha = smoothstep(end_soft        - s.fw, end + s.fw, s.signed_distance);
        let alpha = outer_alpha - inner_alpha;
        return alpha;
      }
    `,
  },
  t: {
    uniformType: 'vec4f',
    defaultValue: [0.1, 0.3, 0.6, 0.8],
    getFn: (name: string) => `
      fn ${name}(s: Sample) -> f32 {
        let start_soft = u.${name}.x;
        let start = u.${name}.y;
        let end = u.${name}.z;
        let end_soft = u.${name}.w;

        // Normalize s.angle to [0, TAU) — handles -2PI..+2PI input
        let t = s.norm_arc_blended;

        // Same logic as for angle
        let local_t        = (((t        - start_soft) % 1) + 1) % 1;
        let local_start    = (((start    - start_soft) % 1) + 1) % 1;
        let local_end      = (((end      - start_soft) % 1) + 1) % 1;
        let local_end_soft = (((end_soft - start_soft) % 1) + 1) % 1;
        // local_start_soft is implicitly 0.0

        let rise  = smoothstep(              -s.fw, local_start    + s.fw, local_t);
        let fall  = smoothstep(local_end - s.fw, local_end_soft + s.fw, local_t);
        return rise * (1.0 - fall);

      }
    `,
  },
}

export function getDeclarationCode(inputNames: string[]): string {
  const codeEntires = inputNames.map((name) => [
    name,
    INPUT_TYPES[name[0] as keyof typeof INPUT_TYPES].uniformType,
  ])

  return codeEntires.map(([name, type]) => `${name}: ${type}`).join(`,\n`)
}

export function getFunctionCode(inputNames: string[]): string {
  return inputNames
    .map((name) => INPUT_TYPES[name[0] as keyof typeof INPUT_TYPES].getFn(name))
    .join('\n')
}

// inputsName is provided to keep the order(super improtant for buffers)
// oherwise we would need to use map for inputs and it's probalematic while working with JSON.stirngify
export function getBuffers(orderedInputNames: string[], inputs: ProgramInputs['props']) {
  const props: ProgramInputs['props'] = {}
  const buffer = [0 /* sdf texture scale */, 1 /* opacity */]
  let minDistance = -Logic.SKELETON_LINE_WIDTH * 0.5

  orderedInputNames.forEach((name) => {
    props[name] = inputs[name] || INPUT_TYPES[name[0] as keyof typeof INPUT_TYPES].defaultValue
    const rawVal = props[name]
    // x, y, z, w
    // if y AND z == null, then treat y as infinite distance
    // prettier-ignore
    const y = rawVal[1] === null ? (rawVal[0] === null ? Logic.INFINITE_DISTANCE : rawVal[2]) : rawVal[1]
    const z = rawVal[2] === null ? rawVal[1] : rawVal[2]

    if (y == null || z == null) {
      throw Error(
        `At least one component (y/z) has to be a number. Provided vector ${rawVal}. inputs: ${inputs}`
      )
    }

    const value = [rawVal[0] === null ? y : rawVal[0], y, z, rawVal[3] === null ? z : rawVal[3]]

    const leftSpace = 4 - (buffer.length % 4)
    if (value.length > leftSpace) {
      buffer.push(...Array(leftSpace).fill(0))
    }
    buffer.push(...value)

    if (name[0] === 'd') {
      minDistance = Math.min(minDistance, value[3])
    }
  })

  const leftSpace = 4 - (buffer.length % 4)
  buffer.push(...Array(leftSpace).fill(0))

  return {
    props,
    orderedInputNames,
    drawBuffer: new Float32Array(buffer),
    pickBuffer: new Float32Array([0 /* sdf scale*/, Logic.INFINITE_DISTANCE, minDistance]),
  }
}
