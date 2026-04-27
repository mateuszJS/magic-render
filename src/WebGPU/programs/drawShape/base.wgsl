const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;
const FWIDTH_VALID_LIMIT = 3.402823466e+10;
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

// @group(0) @binding(1) var texture: texture_storage_2d<rgba32float, read>;
@group(0) @binding(1) var texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;
@group(0) @binding(4) var<storage, read> uniform_t: array<f32>;
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

const BILINEAR_T_THRESHOLD = 1.5;
const BILINEAR_T_THRESHOLD_POS = 2;
// all texels which has diff with nearest texel < BILINEAR_T_THRESHOLD
// will be included in bilinear interpolation.
// It helps avoid interpolating t from totally different places

struct Sample {
  t: f32,
  distance: f32,
};

// Given a uniform arc-length value, binary search uniform_t to find the
// corresponding c_g (curve_index + local_t) value.
fn uniform_t_to_relative_t(s: f32) -> f32 {
  let len = arrayLength(&uniform_t);
  var lo = 0u;
  var hi = len - 1u;
  while (lo + 1u < hi) {
    let mid = (lo + hi) / 2u;
    if (uniform_t[mid] <= s) { lo = mid; } else { hi = mid; }
  }
  let t_lo = uniform_t[lo];
  let t_hi = uniform_t[hi];
  let frac = select(0.0, (s - t_lo) / (t_hi - t_lo), t_hi > t_lo);
  // lo index maps to: curve = lo/4, quarter = lo%4
  let ci = lo / u32(UNIFORM_T_SAMPLING);
  let quarter = lo % u32(UNIFORM_T_SAMPLING);
  let local_t = (f32(quarter) + frac) / UNIFORM_T_SAMPLING;
  return f32(ci) + local_t;
}

fn getSample(pos: vec2f) -> Sample {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let max_coord = vec2i(textureDimensions(texture)) - vec2i(1, 1);


  let p00 = vec2u(clamp(vec2i(floor_pos),                   vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  // let c00 = textureLoad(texture, p00, 0);
  // let c10 = textureLoad(texture, p10, 0);
  // let c01 = textureLoad(texture, p01, 0);
  // let c11 = textureLoad(texture, p11, 0);
  
  // We can drop that abs - 1, because actually we won't rely on that anymroe it doesn't work well
  let c00_g = abs(textureLoad(texture, p00, 0).r) - 1;
  let c10_g = abs(textureLoad(texture, p10, 0).r) - 1;
  let c01_g = abs(textureLoad(texture, p01, 0).r) - 1;
  let c11_g = abs(textureLoad(texture, p11, 0).r) - 1;

  let pos00 = g_to_bezier_pos(c00_g + 1);
  let pos10 = g_to_bezier_pos(c10_g + 1);
  let pos01 = g_to_bezier_pos(c01_g + 1);
  let pos11 = g_to_bezier_pos(c11_g + 1);

  let d00 = max(1e-6, length(pos00 - pos));
  let d10 = max(1e-6, length(pos10 - pos));
  let d01 = max(1e-6, length(pos01 - pos));
  let d11 = max(1e-6, length(pos11 - pos));
  
  let nearest_g_by_pos = select(
    select(c00_g, c10_g, d10 < d00),
    select(c01_g, c11_g, d11 < d01),
    min(d01, d11) < min(d00, d10)
  );
  let nearest_pos = select(
    select(pos00, pos10, d10 < d00),
    select(pos01, pos11, d11 < d01),
    min(d01, d11) < min(d00, d10)
  );
  let nearest_tan = g_to_bezier_tangent(nearest_g_by_pos + 1);
  // Left-normal of tangent points inward for CCW winding
  let inward_normal = vec2f(-nearest_tan.y, nearest_tan.x);
  let nearest_sign = sign(dot(pos - nearest_pos, inward_normal));


  let tan00 = g_to_bezier_tangent(c00_g + 1);
  let tan10 = g_to_bezier_tangent(c10_g + 1);
  let tan01 = g_to_bezier_tangent(c01_g + 1);
  let tan11 = g_to_bezier_tangent(c11_g + 1);
  let a00 = atan2(tan00.y, tan00.x);
  let a10 = atan2(tan10.y, tan10.x);
  let a01 = atan2(tan01.y, tan01.x);
  let a11 = atan2(tan11.y, tan11.x);

  let naerest_tan = g_to_bezier_tangent(nearest_g_by_pos + 1);
  let nearest_tan_a = atan2(naerest_tan.y, naerest_tan.x);

  let diff00 = a00 - nearest_tan_a;
  let diff10 = a10 - nearest_tan_a;
  let diff01 = a01 - nearest_tan_a;
  let diff11 = a11 - nearest_tan_a;
  // Normalize to (-PI, PI] to handle wraparound
  let ndiff00 = diff00 - round(diff00 / (2.0 * PI)) * (2.0 * PI);
  let ndiff10 = diff10 - round(diff10 / (2.0 * PI)) * (2.0 * PI);
  let ndiff01 = diff01 - round(diff01 / (2.0 * PI)) * (2.0 * PI);
  let ndiff11 = diff11 - round(diff11 / (2.0 * PI)) * (2.0 * PI);

  let _diff00 = abs(get_uniform_t(c00_g) - get_uniform_t(nearest_g_by_pos));
  let _diff10 = abs(get_uniform_t(c10_g) - get_uniform_t(nearest_g_by_pos));
  let _diff01 = abs(get_uniform_t(c01_g) - get_uniform_t(nearest_g_by_pos));
  let _diff11 = abs(get_uniform_t(c11_g) - get_uniform_t(nearest_g_by_pos));
  // TODO: blend uniform_t, not raw t




  let angle_threshold = PI * 0.7;

  let max_d = max(max(d00, d10), max(d01, d11));
  // let w00 = (max_d - d00) / max_d;
  // let w10 = (max_d - d10) / max_d;
  // let w01 = (max_d - d01) / max_d;
  // let w11 = (max_d - d11) / max_d;

  let w00 = select(0.0, (1.0 - fract_pos.x) * (1.0 - fract_pos.y), _diff00 < BILINEAR_T_THRESHOLD && abs(ndiff00) < angle_threshold);
  let w10 = select(0.0, fract_pos.x         * (1.0 - fract_pos.y), _diff10 < BILINEAR_T_THRESHOLD && abs(ndiff10) < angle_threshold);
  let w01 = select(0.0, (1.0 - fract_pos.x) * fract_pos.y,         _diff01 < BILINEAR_T_THRESHOLD && abs(ndiff01) < angle_threshold);
  let w11 = select(0.0, fract_pos.x         * fract_pos.y,         _diff11 < BILINEAR_T_THRESHOLD && abs(ndiff11) < angle_threshold);

  let total_w = w00 + w10 + w01 + w11;
  let uniform_blended = (get_uniform_t(c00_g) * w00 + get_uniform_t(c10_g) * w10 + get_uniform_t(c01_g) * w01 + get_uniform_t(c11_g) * w11) / total_w;
  let blended = uniform_t_to_relative_t(uniform_blended);

  return Sample(blended, nearest_sign);
  // return Sample(blended, min_dist);
}

// t is abs(g) - 1: floor(t) = curve index, fract(t) = local bezier t in [0,1)
// uniform_t layout: index ci*4+0 is arc length at start of curve ci (cumulative),
// ci*4+1..4 are arc lengths at t=0.25, 0.50, 0.75, 1.00 of that curve.
fn get_uniform_t(t: f32) -> f32 {
  let ci = u32(floor(t));
  let local_t = fract(t);

  // Which quarter of the curve are we in? [0..3]
  let quarter_f = local_t * UNIFORM_T_SAMPLING;
  let quarter = u32(floor(quarter_f));
  let frac = fract(quarter_f);

  let lower_idx = ci * u32(UNIFORM_T_SAMPLING) + quarter;
  let upper_idx = lower_idx + 1u;

  return mix(uniform_t[lower_idx], uniform_t[upper_idx], frac);
}

// Cubic bezier tangent (unnormalized) at local t encoded in g.
fn g_to_bezier_tangent(g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t = fract(abs_g);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  let is_straight_line = p1.x > STRAIGHT_LINE_THRESHOLD;
  if (is_straight_line) {
    return normalize(p3 - p0);
  }


  let mt = 1.0 - t;
  return 3.0 * (mt * mt * (p1 - p0) + 2.0 * mt * t * (p2 - p1) + t * t * (p3 - p2));
}

fn g_to_bezier_pos(g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t   = fract(abs_g);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );


  let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;
  if (is_straight_line) {
    return mix(curve.p0, curve.p3, t);
  }

  return bezier_point(curve, t);
}

// Refines the nearest-curve-point estimate from bilinear t interpolation
// by doing one Newton-Raphson step, minimizing |bezier(t) - pos|².
// For straight lines, computes the exact projection.
fn refine_curve_pos(pos: vec2f, g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t = fract(abs_g);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  if (p1.x > STRAIGHT_LINE_THRESHOLD) {
    let line_vec = p3 - p0;
    let refined_t = clamp(dot(pos - p0, line_vec) / dot(line_vec, line_vec), 0.0, 1.0);
    return mix(p0, p3, refined_t);
  }

  let curve = CubicBezier(p0, p1, p2, p3);
  let orig_pos = bezier_point(curve, t); // store original to ensure not worst results than we already have
  let mt = 1.0 - t;
  let dp  = 3.0 * (mt * mt * (p1 - p0) + 2.0 * mt * t * (p2 - p1) + t * t * (p3 - p2));
  let ddp = 6.0 * ((1.0 - t) * (p2 - 2.0 * p1 + p0) + t * (p3 - 2.0 * p2 + p1)); // ful netwon demonimator (weird artifacts with voershootign if far form curve)
  let diff = orig_pos - pos;
  // Full Newton denominator (includes curvature term) prevents overshooting
  // on the concave side of high-curvature curves.
  let df = dot(dp, dp) + dot(diff, ddp);
  let refined_t = clamp(t - select(0.0, dot(diff, dp) / df, abs(df) > 1e-8), 0.0, 1.0);
  let refined_pos = bezier_point(curve, refined_t);

  // Only accept the refined position if it's strictly closer.
  return select(orig_pos, refined_pos, dot(refined_pos - pos, refined_pos - pos) < dot(orig_pos - pos, orig_pos - pos));
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);
  let g = abs(sdf.t) + 1;
  // let g = textureLoad(texture, texel).g;

  // Decode the nearest curve point stored in this texel, then compute
  // the actual Euclidean distance from the output pixel to that curve point.
  // sign(g): +1 = inside (distance grows inward), -1 = outside (distance < 0)
  let curve_pos = g_to_bezier_pos(g);

  // Refine the bilinear t estimate to the true nearest point on the curve.
  // let curve_pos = refine_curve_pos(vsOut.uv, g);

  let distance = length(curve_pos - vsOut.uv) * -sdf.distance;

  // Grid: fract(uv) tells how far into the current texel we are (0..1).
  // Dividing by fwidth gives distance in screen pixels from the nearest edge.
  let fw = fwidth(vsOut.uv);
  let grid = min(fract(vsOut.uv) / fw, (1.0 - fract(vsOut.uv)) / fw);
  let on_grid = min(grid.x, grid.y) < 0.5;
  // let on_grid = false;

  return vec4f((1 - distance), select(0.0, 1.0, on_grid), 0, 1.0);


  ${TEST}

  let dist_derivative = length(fwidth(vsOut.uv));
  // let dist_derivative = fwidth(distance);

  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT); // if too large -> 0
  let alpha_smooth_factor = max(safe_dist_derivative * 0.5, EPSILON);

  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, distance);
  let outer_alpha = smoothstep(u.dist_end - alpha_smooth_factor, u.dist_end + alpha_smooth_factor, distance);
  let alpha = outer_alpha - inner_alpha;
  let color = getColor(vec4f(distance, sdf.t, 0, 1), vsOut.uv, vsOut.norm_uv);
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
