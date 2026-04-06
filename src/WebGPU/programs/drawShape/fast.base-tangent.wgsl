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

fn bezier_tangent(curve: CubicBezier, t: f32) -> vec2f {
  let one_minus_t = 1.0 - t;
  return 3.0 * one_minus_t * one_minus_t * (curve.p1 - curve.p0) +
         6.0 * one_minus_t * t            * (curve.p2 - curve.p1) +
         3.0 * t           * t            * (curve.p3 - curve.p2);
}

// Straight lines are stored with p1.x = 1e10; handle them explicitly.
fn safe_curve_point(c: CubicBezier, t: f32) -> vec2f {
  if (c.p1.x > STRAIGHT_LINE_THRESHOLD) {
    return mix(c.p0, c.p3, t);
  }
  return bezier_point(c, t);
}

fn safe_curve_tangent(c: CubicBezier, t: f32) -> vec2f {
  if (c.p1.x > STRAIGHT_LINE_THRESHOLD) {
    return c.p3 - c.p0;  // constant direction for a straight line
  }
  return bezier_tangent(c, t);
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

  let w00 = select(0.0, (1.0 - fract_pos.x) * (1.0 - fract_pos.y), abs(c00.g - nearest_g) < BILINEAR_T_THRESHOLD);
  let w10 = select(0.0, fract_pos.x         * (1.0 - fract_pos.y), abs(c10.g - nearest_g) < BILINEAR_T_THRESHOLD);
  let w01 = select(0.0, (1.0 - fract_pos.x) * fract_pos.y,         abs(c01.g - nearest_g) < BILINEAR_T_THRESHOLD);
  let w11 = select(0.0, fract_pos.x         * fract_pos.y,         abs(c11.g - nearest_g) < BILINEAR_T_THRESHOLD);

  let total_w = w00 + w10 + w01 + w11;
  let blended = (c00 * w00 + c10 * w10 + c01 * w01 + c11 * w11) / total_w;
  return blended;

  // let pos_count = i32(c00.g > 0.0) + i32(c10.g > 0.0) + i32(c01.g > 0.0) + i32(c11.g > 0.0);
  // let majority_sign = select(-1.0, 1.0, pos_count >= 2);
  // return vec4f(blended.r, abs(blended.g) * majority_sign, blended.b, blended.a);
}


@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);

  let _unused = arrayLength(&curves);
  let dist_to_curve = sign(sdf.g);

  // --- Tangent-directed interpolation ---
  // 1. Find the nearest texel (no bilinear mixing of t).
  let floor_pos  = floor(vsOut.uv - 0.5);
  let fract_pos  = vsOut.uv - 0.5 - floor_pos;
  let max_coord  = vec2i(textureDimensions(texture)) - vec2i(1, 1);

  let g00 = textureLoad(texture, vec2u(clamp(vec2i(floor_pos),                 vec2i(0,0), max_coord))).g;
  let g10 = textureLoad(texture, vec2u(clamp(vec2i(floor_pos + vec2f(1,0)),    vec2i(0,0), max_coord))).g;
  let g01 = textureLoad(texture, vec2u(clamp(vec2i(floor_pos + vec2f(0,1)),    vec2i(0,0), max_coord))).g;
  let g11 = textureLoad(texture, vec2u(clamp(vec2i(floor_pos + vec2f(1,1)),    vec2i(0,0), max_coord))).g;

  let nearest_g = select(
    select(g00, g10, fract_pos.x >= 0.5),
    select(g01, g11, fract_pos.x >= 0.5),
    fract_pos.y >= 0.5
  );

  // 2. Reconstruct nearest curve point and tangent.
  let n_abs_g       = abs(nearest_g);
  let n_curve_floor = floor(n_abs_g);          // encoded floor = curve_idx + 1
  let n_curve_idx   = u32(n_curve_floor) - 1u; // 0-based curve index
  let n_t           = fract(n_abs_g);
  let n_curve       = CubicBezier(
    curves[n_curve_idx * 4 + 0], curves[n_curve_idx * 4 + 1],
    curves[n_curve_idx * 4 + 2], curves[n_curve_idx * 4 + 3]
  );
  let nearest_pos  = safe_curve_point(n_curve, n_t);
  let raw_tangent  = safe_curve_tangent(n_curve, n_t);
  let tangent      = select(raw_tangent, normalize(raw_tangent), dot(raw_tangent, raw_tangent) > 1e-12);

  // 3. Pick the horizontal and vertical neighbors of the nearest texel.
  //    (the neighbor that shares the opposite x- or y-half of the quad)
  let h_g = select(
    select(g10, g00, fract_pos.x >= 0.5),   // y < 0.5: p00↔p10
    select(g11, g01, fract_pos.x >= 0.5),   // y ≥ 0.5: p01↔p11
    fract_pos.y >= 0.5
  );
  let v_g = select(
    select(g01, g00, fract_pos.y >= 0.5),   // x < 0.5: p00↔p01
    select(g11, g10, fract_pos.y >= 0.5),   // x ≥ 0.5: p10↔p11
    fract_pos.x >= 0.5
  );

  // Guard: only blend if same curve (compare encoded floor values) and t within 0.5.
  let h_abs_g = abs(h_g);
  let v_abs_g = abs(v_g);
  let h_ok = floor(h_abs_g) == n_curve_floor && abs(fract(h_abs_g) - n_t) < 0.5;
  let v_ok = floor(v_abs_g) == n_curve_floor && abs(fract(v_abs_g) - n_t) < 0.5;

  let h_curve_idx = u32(floor(h_abs_g)) - 1u;
  let v_curve_idx = u32(floor(v_abs_g)) - 1u;
  let h_curve = CubicBezier(curves[h_curve_idx * 4 + 0], curves[h_curve_idx * 4 + 1], curves[h_curve_idx * 4 + 2], curves[h_curve_idx * 4 + 3]);
  let v_curve = CubicBezier(curves[v_curve_idx * 4 + 0], curves[v_curve_idx * 4 + 1], curves[v_curve_idx * 4 + 2], curves[v_curve_idx * 4 + 3]);
  let h_pos_raw = safe_curve_point(h_curve, fract(h_abs_g));
  let v_pos_raw = safe_curve_point(v_curve, fract(v_abs_g));
  let h_pos = select(nearest_pos, h_pos_raw, h_ok);
  let v_pos = select(nearest_pos, v_pos_raw, v_ok);

  // 4. Blend weight = |tangent component| × pixel's fractional offset toward that neighbor.
  //    Offset is normalized to [0,1]: 0 = pixel is on nearest texel, 1 = pixel is on that neighbor.
  let h_offset = select(fract_pos.x, 1.0 - fract_pos.x, fract_pos.x >= 0.5) * 2.0;
  let v_offset = select(fract_pos.y, 1.0 - fract_pos.y, fract_pos.y >= 0.5) * 2.0;
  let h_w = abs(tangent.x) * h_offset;
  let v_w = abs(tangent.y) * v_offset;

  // Weighted average: nearest always participates with weight 1.
  let blended_pos = (nearest_pos + h_w * h_pos + v_w * v_pos) / (1.0 + h_w + v_w);
  let min_dist    = min(length(nearest_pos - vsOut.uv), length(blended_pos - vsOut.uv));

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
