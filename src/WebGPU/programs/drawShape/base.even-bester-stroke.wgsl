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

struct BezierEval {
  p: vec2f,
  dp: vec2f,   // P'(t)
  ddp: vec2f,  // P''(t)
}

fn bezier_eval_all(curve: CubicBezier, t: f32) -> BezierEval {
  let b0 = mix(curve.p0, curve.p1, t);
  let b1 = mix(curve.p1, curve.p2, t);
  let b2 = mix(curve.p2, curve.p3, t);
  let c0 = mix(b0, b1, t);
  let c1 = mix(b1, b2, t);
  var result: BezierEval;
  result.p   = mix(c0, c1, t);
  result.dp  = 3.0 * (c1 - c0);
  result.ddp = 6.0 * (b0 - 2.0 * b1 + b2);
  return result;
}

// Refine an initial t guess to the true closest point using Newton-Raphson
fn refine_closest_t(point: vec2f, curve: CubicBezier, initial_t: f32) -> f32 {
  var t = initial_t;
  for (var i = 0; i < 3; i++) {
    let ev = bezier_eval_all(curve, t);
    let diff = ev.p - point;
    let f   = dot(diff, ev.dp);
    let df  = dot(ev.dp, ev.dp) + dot(diff, ev.ddp);
    let step = select(f / df, 0.0, abs(df) < 1e-8);
    t = clamp(t - step, 0.0, 1.0);
  }
  return t;
}

fn bezier_tangent(curve: CubicBezier, t: f32) -> vec2f {
  let one_minus_t = 1.0 - t;
  return 3.0 * one_minus_t * one_minus_t * (curve.p1 - curve.p0) +
         6.0 * one_minus_t * t            * (curve.p2 - curve.p1) +
         3.0 * t           * t            * (curve.p3 - curve.p2);
}

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

fn g_to_curve_pos(g: f32) -> vec2f {
  let abs_g = abs(g);
  let curve_index = u32(abs_g) - 1u;
  let curve_t = fract(abs_g);
  let curve = CubicBezier(
    curves[curve_index * 4 + 0],
    curves[curve_index * 4 + 1],
    curves[curve_index * 4 + 2],
    curves[curve_index * 4 + 3]
  );
  return bezier_point(curve, curve_t);
}

fn g_to_refined_dist(g: f32, pixel: vec2f) -> f32 {
  let abs_g = abs(g);
  let curve_index = u32(abs_g) - 1u;
  let curve_t = fract(abs_g);
  let curve = CubicBezier(
    curves[curve_index * 4 + 0],
    curves[curve_index * 4 + 1],
    curves[curve_index * 4 + 2],
    curves[curve_index * 4 + 3]
  );
  let refined_t = refine_closest_t(pixel, curve, curve_t);
  return length(bezier_point(curve, refined_t) - pixel);
}

// NR-refine distance from each of the 4 neighboring texels and return minimum.
// This covers junction pixels where the nearest curve may differ from nearest_g.
fn getMinRefinedDist(pos: vec2f, pixel: vec2f) -> f32 {
  let floor_pos = floor(pos - 0.5);
  let max_coord = vec2i(textureDimensions(texture)) - vec2i(1, 1);

  let p00 = vec2u(clamp(vec2i(floor_pos),                   vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  let d00 = g_to_refined_dist(textureLoad(texture, p00).g, pixel);
  let d10 = g_to_refined_dist(textureLoad(texture, p10).g, pixel);
  let d01 = g_to_refined_dist(textureLoad(texture, p01).g, pixel);
  let d11 = g_to_refined_dist(textureLoad(texture, p11).g, pixel);

  return min(min(d00, d10), min(d01, d11));
}

fn getSample(pos: vec2f) -> vec4f {
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
  let nearest_curve_index = floor(abs(nearest_g));

  // Only blend texels on the same curve as the nearest texel
  let same00 = floor(abs(c00.g)) == nearest_curve_index;
  let same10 = floor(abs(c10.g)) == nearest_curve_index;
  let same01 = floor(abs(c01.g)) == nearest_curve_index;
  let same11 = floor(abs(c11.g)) == nearest_curve_index;

  let w00 = select(0.0, (1.0 - fract_pos.x) * (1.0 - fract_pos.y), same00);
  let w10 = select(0.0, fract_pos.x         * (1.0 - fract_pos.y), same10);
  let w01 = select(0.0, (1.0 - fract_pos.x) * fract_pos.y,         same01);
  let w11 = select(0.0, fract_pos.x         * fract_pos.y,         same11);

  let total_w = w00 + w10 + w01 + w11;
  let blended = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / total_w;

  // Blend fract(abs(g)) directly to avoid sign-flip corruption when mixing
  // inside/outside texels of the same curve
  let smooth_t = (fract(abs(c00.g)) * w00 + fract(abs(c10.g)) * w10 +
                  fract(abs(c01.g)) * w01 + fract(abs(c11.g)) * w11) / total_w;
  let smooth_g = sign(nearest_g) * (nearest_curve_index + smooth_t);

  return vec4f(blended.r, smooth_g, blended.b, blended.a);

  // let pos_count = i32(c00.g > 0.0) + i32(c10.g > 0.0) + i32(c01.g > 0.0) + i32(c11.g > 0.0);
  // let majority_sign = select(-1.0, 1.0, pos_count >= 2);
  // return vec4f(blended.r, abs(blended.g) * majority_sign, blended.b, blended.a);
}


@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);
  // let sdf = textureLoad(texture, vec2i(vsOut.uv));

  let _unused = arrayLength(&curves);
  let abs_g = abs(sdf.g);
  let curve_index = u32(abs_g) - 1u;
  let curve_t = fract(abs_g);
  

  let curve = CubicBezier(
    curves[curve_index * 4 + 0],
    curves[curve_index * 4 + 1],
    curves[curve_index * 4 + 2],
    curves[curve_index * 4 + 3]
  );
  

  // Refine t with NR — curve_index is nearest-neighbor locked so it won't diverge
  let refined_t = refine_closest_t(vsOut.uv, curve, curve_t);
  let pos = bezier_point(curve, refined_t);
  let tangent = bezier_tangent(curve, refined_t);
  let to_pixel = vsOut.uv - pos;
  // 2D cross product: tangent x to_pixel — positive = left side, negative = right side
  let side = tangent.x * to_pixel.y - tangent.y * to_pixel.x;
  let dist_to_curve = sign(side);

  let min_dist = getMinRefinedDist(vsOut.uv, vsOut.uv);
  if (min_dist < 0.2) {
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
  let color = getColor(sdf, vsOut.uv, vsOut.norm_uv);
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
