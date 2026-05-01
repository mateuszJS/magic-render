const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;
const FWIDTH_VALID_LIMIT = 100;
// Shapes share a single SDF texture. Pixels not covered by any shape are
// initialized to -3.402823466e+38 before per-shape SDF values are written.
// This creates extremely large distance derivatives at the boundary between
// real shape SDF values and the default background value, so we ignore
// derivatives larger than FWIDTH_VALID_LIMIT.

const UNIFORM_T_SAMPLING = 4.0;

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

fn bezier_point(curve: CubicBezier, t: f32) -> vec2f {
  let t2 = t * t;
  let t3 = t2 * t;
  let one_minus_t = 1.0 - t;
  let one_minus_t2 = one_minus_t * one_minus_t;
  let one_minus_t3 = one_minus_t2 * one_minus_t;

  return curve.p0 * one_minus_t3 +
         3.0 * curve.p1 * t * one_minus_t2 +
         3.0 * curve.p2 * t2 * one_minus_t +
         curve.p3 * t3;
}


struct Vertex {
  @location(0) position: vec4f,
};

// @group(0) @binding(0) var ourSampler: sampler;
@group(0) @binding(1) var texture: texture_2d<f32>;
// @group(0) @binding(1) var texture: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;
// @group(0) @binding(4) var<storage, read> uniform_t: array<f32>;
// @group(0) @binding(5) var ourSampler: sampler;
// consider witchign to uniform if possible

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) norm_uv: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  let size = textureDimensions(texture);
  return VSOutput(
    camera_projection * vec4f(vert.position.xy, 0.0, 1.0),
    vert.position.zw * (vec2f(size) + vec2f(0)),
    vert.position.zw,
  );
}

const BILINEAR_T_THRESHOLD = 1;
const BILINEAR_T_THRESHOLD_POS = 2;
// all texels which has diff with nearest texel < BILINEAR_T_THRESHOLD
// will be included in bilinear interpolation.
// It helps avoid interpolating t from totally different places

struct Sample {
  t: f32,
  sign: f32,
};

fn getSample(pos: vec2f) -> Sample {
    let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let max_coord = vec2i(vec2i(textureDimensions(texture)) - vec2i(1, 1));

  let p00 = vec2u(clamp(vec2i(floor_pos                  ), vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  // textureSample(ourTexture, ourSampler, fsInput.texcoord);
  let raw_c00 = textureLoad(texture, p00, 0).r;
  let raw_c10 = textureLoad(texture, p10, 0).r;
  let raw_c01 = textureLoad(texture, p01, 0).r;
  let raw_c11 = textureLoad(texture, p11, 0).r;

  let c00 = abs(raw_c00) - 1;
  let c10 = abs(raw_c10) - 1;
  let c01 = abs(raw_c01) - 1;
  let c11 = abs(raw_c11) - 1;

  let g10 = select(c00, c10, abs(c10 - c00) < BILINEAR_T_THRESHOLD);
  let g01 = select(c00, c01, abs(c01 - c00) < BILINEAR_T_THRESHOLD);
  let g11 = select(c00, c11, abs(c11 - c00) < BILINEAR_T_THRESHOLD);

  let top = mix(c00, g10, fract_pos.x);
  let bottom = mix(g01, g11, fract_pos.x);
  let final_t = mix(top, bottom, fract_pos.y);

  // Pick sign from the nearest texel to pos (not always p00)
  let nearest_raw = select(
    select(raw_c00, raw_c01, fract_pos.y >= 0.5),
    select(raw_c10, raw_c11, fract_pos.y >= 0.5),
    fract_pos.x >= 0.5
  );

  return Sample(final_t, sign(nearest_raw));
}

fn g_to_bezier_pos(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let local_t = fract(global_t);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );

  let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;
  if (is_straight_line) {
    return mix(curve.p0, curve.p3, local_t);
  }

  return bezier_point(curve, local_t);
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sample = getSample(vsOut.uv);
  let curve_pos = g_to_bezier_pos(sample.t);
  let distance = length(curve_pos - vsOut.uv);
  let signed_distance = distance * sample.sign;

  ${TEST}

  let dist_derivative = fwidth(signed_distance);

  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT); // if too large -> 0
  let alpha_smooth_factor = safe_dist_derivative * 1;
  // let alpha_smooth_factor = max(safe_dist_derivative * 1, EPSILON);

  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, signed_distance);
  let outer_alpha = smoothstep(u.dist_end - alpha_smooth_factor, u.dist_end + alpha_smooth_factor, signed_distance);
  let alpha = outer_alpha - inner_alpha;
  let color = getColor(vec4f(signed_distance, 0, 0, 1), vsOut.uv, vsOut.norm_uv);
  let result = vec4f(color.rgb, color.a * alpha);

  // if (result.a < EPSILON) {
  //   return vec4f(0.5);
  // }

  return result;

  // let stroke_factor = select(0.5, 0.0, sdf.g > 1.0);
  // color = vec4f(0, sdf.g % 1, 0, 1.0);
  // color = vec4f(0, 0, sdf.b / (2 * PI), 1.0);
  // color = vec4f(sdf.r / 100.0, sdf.g % 1, sdf.b / (2 * PI), 1.0);
  // color = select(vec4f(0.5, 0, 0, 1), vec4f(0, 0, 0.5, 1), u32(sdf.r / 20.0) % 2 == 0);
}
