const STRAIGHT_LINE_THRESHOLD = 1e10;

// local_t, used to test if "t" is on p0 or p3
const T_EPSILON = 1e-5;


struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

fn t_to_pos(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let t   = fract(global_t);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );

  if (is_straight_line_marker(curve.p1)) {
    return mix(curve.p0, curve.p3, t);
  }
  return bezier_point(curve, t);
}


// returns unit vector tangent at global t
fn t_to_tan(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let t = fract(global_t);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  if (is_straight_line_marker(p1)) {
    let chord = p3 - p0;
    let len_sq = dot(chord, chord);
    return select(vec2f(1.0, 0.0), chord * inverseSqrt(len_sq), len_sq > 1e-12);
  }

  let mt = 1.0 - t;
  let deriv = 3.0 * (mt * mt * (p1 - p0) + 2.0 * mt * t * (p2 - p1) + t * t * (p3 - p2));
  let deriv_len_sq = dot(deriv, deriv);

  if (deriv_len_sq >= 1e-12) {
    return deriv * inverseSqrt(deriv_len_sq);
  }

  // First derivative vanished. Use the second derivative — that's what the
  // curve actually does next. For a cubic:
  //   B''(t) = 6 * ((1-t)*(P2 - 2*P1 + P0) + t*(P3 - 2*P2 + P1))
  //   B''(0) = 6 * (P2 - 2*P1 + P0)
  //   B''(1) = 6 * (P3 - 2*P2 + P1)
  // The leading constant 6 is irrelevant for normalisation.
  let dd = mt * (p2 - 2.0 * p1 + p0) + t * (p3 - 2.0 * p2 + p1);
  let dd_len_sq = dot(dd, dd);

  if (dd_len_sq >= 1e-12) {
    // At t=1 endpoint with P2 == P3, B'' points from P3 back toward P1, so
    // the "direction of motion approaching t=1" is the negative. Flip sign
    // when we're at the t=1 endpoint specifically — for interior t, both
    // B' and B'' point along the curve direction as t increases.
    let sign = select(1.0, -1.0, t > 0.5 && deriv_len_sq < 1e-12);
    return dd * sign * inverseSqrt(dd_len_sq);
  }

  // Both B' and B'' vanished (e.g. P0 == P1 == P2). Cubic's third
  // derivative is constant: B'''(t) = 6 * (P3 - 3*P2 + 3*P1 - P0). Use that.
  let ddd = p3 - 3.0 * p2 + 3.0 * p1 - p0;
  let ddd_len_sq = dot(ddd, ddd);
  return select(vec2f(1.0, 0.0), ddd * inverseSqrt(ddd_len_sq), ddd_len_sq > 1e-12);
}


// Centralised straight-line sentinel test. If the encoding ever changes, fix
// it here and every consumer (g_to_bezier_tangent / g_to_bezier_pos /
// refine_curve_pos / corner branch) follows.
fn is_straight_line_marker(p1: vec2f) -> bool {
  return p1.x > STRAIGHT_LINE_THRESHOLD;
}


fn prev_curve_in_path(cur_idx: u32) -> u32 {
  // Alternative version of this function(look for next path) lives in renderShapeSdf/shader.wgsl
  let num_curves = arrayLength(&curves) / 4;
  let cur_p0 = curves[cur_idx * 4u + 0u];
  let candidate_prev = (cur_idx + num_curves - 1u) % num_curves;
  let candidate_p3 = curves[candidate_prev * 4u + 3u];
  let bridge = candidate_p3 - cur_p0;

  if (dot(bridge, bridge) < T_EPSILON) {
    return candidate_prev;
  }

  // cur_idx is the first curve of its path. Walk forward looking for the LAST
  // curve of this path: a curve i whose p3 doesn't match the next curve's p0.
  var i = cur_idx;
  for (var k = 0u; k < num_curves; k = k + 1u) {
    let next_i  = (i + 1u) % num_curves;
    let i_p3    = curves[i * 4u + 3u];
    let next_p0 = curves[next_i * 4u + 0u];
    let gap     = i_p3 - next_p0;
    if (dot(gap, gap) > T_EPSILON) { return i; }
    i = next_i;
  }
  // Single-curve "path" or fully connected ring — fall back to the simple wrap.
  return candidate_prev;
}

// returns -1 (outside) or 1(inside)
// t -> t of the closest point on curve
// uv -> position of the currently claculated pixel
// tan -> tangent of the closest point on curve
// pos -> position of the closest point on curve
fn get_is_inside(uv: vec2f, t: f32, tan: vec2f, pos: vec2f) -> f32 {
  let inward_normal = vec2f(tan.y, -tan.x); // 90 degree CCW,
  // inward -> something moving towards from the center(shape), towards the interior

  // pos - uv points towards curve, so different direction base if inside or outside.
  // Dot will return 1 if direction is towards the inside. This is true onyl for exterior pixels, all pixels insdie shape
  // will point toward closest curve, so exterior, that's why we multiply by -1
  var is_inside = -sign(dot(pos - uv, inward_normal));
  
  if (fract(t) < T_EPSILON) {
    // when corner is sharp(or just tangent discontinue), then for many pixels the closest point will be local_t = 0, singular point
    // of the current path, but it causes issues when actually the previous path should be used
    // see ./artifacts/cave incorrect path.png and ./artifacts/exterior incorrect path.png
    let num_curves = arrayLength(&curves) / 4;
    let cur_idx = u32(t) % num_curves;
    let prev_idx = prev_curve_in_path(cur_idx);
    let prev_max_t = f32(prev_idx) + 1 - T_EPSILON;
    let prev_tan = t_to_tan(prev_max_t);
    
    let cross_2d = tan.x * prev_tan.y - prev_tan.x * tan.y;
    // cross2d = curr x prev. CW winding in Y-down:
    //   > 0 → conves, like exterior pixels around the rect corner(outside the shape)
    //   < 0 → concave, like interior pixels around the rect corner(inside the shape)
    //   ≈ 0 → near-collinear → both branches give the same answer.
    // WARNING: it only works because of CW paths + Y-up coordinates.

    let sign_cur  = sign(dot(uv - pos, inward_normal));
    // for exterior pixels, uv - pos points toward exterior

    let prev_normal = vec2f(prev_tan.y, -prev_tan.x);
    let sign_prev = sign(dot(uv - pos, prev_normal));
  
    is_inside = select(
      min(sign_cur, sign_prev),
      max(sign_cur, sign_prev),
      cross_2d < 0.0
    );
  }

  return is_inside;
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
