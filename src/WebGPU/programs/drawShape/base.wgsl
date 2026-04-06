const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;
const FWIDTH_VALID_LIMIT = 3.402823466e+10;
// Shapes share a single SDF texture. Pixels not covered by any shape are
// initialized to -3.402823466e+38 before per-shape SDF values are written.
// This creates extremely large distance derivatives at the boundary between
// real shape SDF values and the default background value, so we ignore
// derivatives larger than FWIDTH_VALID_LIMIT.

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

@group(0) @binding(1) var texture: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;
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

const BILINEAR_T_THRESHOLD = 0.5;
// all texels which has diff with nearest texel < BILINEAR_T_THRESHOLD
// will be included in bilinear interpolation.
// It helps avoid interpolating t from totally different places

struct Sample {
  t: f32,
  distance: f32,
};

fn getSample(pos: vec2f) -> Sample {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let max_coord = vec2i(textureDimensions(texture)) - vec2i(1, 1);


  let p00 = vec2u(clamp(vec2i(floor_pos),                   vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  let c00 = textureLoad(texture, p00);
  let c10 = textureLoad(texture, p10);
  let c01 = textureLoad(texture, p01);
  let c11 = textureLoad(texture, p11);

  let nearest_g = select(
    select(c00.g, c10.g, fract_pos.x >= 0.5),
    select(c01.g, c11.g, fract_pos.x >= 0.5),
    fract_pos.y >= 0.5
  );

  // let w00 = select(0.0, (1.0 - fract_pos.x) * (1.0 - fract_pos.y), abs(c00.g - nearest_g) < BILINEAR_T_THRESHOLD);
  // let w10 = select(0.0, fract_pos.x         * (1.0 - fract_pos.y), abs(c10.g - nearest_g) < BILINEAR_T_THRESHOLD);
  // let w01 = select(0.0, (1.0 - fract_pos.x) * fract_pos.y,         abs(c01.g - nearest_g) < BILINEAR_T_THRESHOLD);
  // let w11 = select(0.0, fract_pos.x         * fract_pos.y,         abs(c11.g - nearest_g) < BILINEAR_T_THRESHOLD);
  let w00 = (1.0 - fract_pos.x) * (1.0 - fract_pos.y);
  let w10 = fract_pos.x         * (1.0 - fract_pos.y);
  let w01 = (1.0 - fract_pos.x) * fract_pos.y;
  let w11 = fract_pos.x         * fract_pos.y;

  let total_w = w00 + w10 + w01 + w11;
  let blended = (c00.g * w00 + c10.g * w10 + c01.g * w01 + c11.g * w11) / total_w;



  let pos00 = g_to_bezier_pos(c00.g);
  let pos10 = g_to_bezier_pos(c10.g);
  let pos01 = g_to_bezier_pos(c01.g);
  let pos11 = g_to_bezier_pos(c11.g);

  let d00 = length(pos00 - pos);
  let d10 = length(pos10 - pos);
  let d01 = length(pos01 - pos);
  let d11 = length(pos11 - pos);

  let min_dist = min(min(d00, d10), min(d01, d11));


  return Sample(blended, min_dist);
}


fn g_to_bezier_pos(g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t   = fract(abs_g);
  return bezier_point(CubicBezier(
    curves[idx * 4 + 0], curves[idx * 4 + 1],
    curves[idx * 4 + 2], curves[idx * 4 + 3]
  ), t);
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);

  let dist_to_curve = sign(sdf.t);

  if (sdf.distance < 0.2) {
    return vec4f(0, 0, 1, 1);
  }

  return vec4f(-dist_to_curve, dist_to_curve, 0, 1.0);
  // return vec4f(sdf.r, 0, 0, 1.0);
  




  ${TEST}

  let dist_derivative = fwidth(dist_to_curve);

  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT); // if too large -> 0
  let alpha_smooth_factor = max(safe_dist_derivative * 0.5, EPSILON);

  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, dist_to_curve);
  let outer_alpha = smoothstep(u.dist_end - alpha_smooth_factor, u.dist_end + alpha_smooth_factor, dist_to_curve);
  let alpha = outer_alpha - inner_alpha;
  let color = getColor(vec4f(sdf.distance, sdf.t, 0, 1), vsOut.uv, vsOut.norm_uv);
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
