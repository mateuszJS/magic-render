const STRAIGHT_LINE_THRESHOLD = 1e10;

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

@group(0) @binding(0) var<storage, read> curves: array<vec2f>;

struct VSOutput {
  @builtin(position) position: vec4f,
};

@vertex fn vs(@builtin(vertex_index) idx: u32) -> VSOutput {
  var pos = array<vec2f, 6>(
    vec2f(-1.0, -1.0), vec2f( 1.0, -1.0), vec2f(-1.0,  1.0),
    vec2f(-1.0,  1.0), vec2f( 1.0, -1.0), vec2f( 1.0,  1.0),
  );
  return VSOutput(vec4f(pos[idx], 0.0, 1.0));
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) f32 {
  return evaluate_shape(vsOut.position.xy);
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

// Evaluate P(t), P'(t) and P''(t) in one de Casteljau pass.
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

// Find closest point on cubic Bézier: Newton-Raphson on f(t)=dot(P(t)-q, P'(t))=0
fn closest_point_on_bezier(point: vec2f, curve: CubicBezier) -> f32 {
  var best_t = initial_guess_closest_point(point, curve);

  for (var i = 0; i < 4; i++) {
    let ev = bezier_eval_all(curve, best_t);
    let diff = ev.p - point;
    let f   = dot(diff, ev.dp);
    let df  = dot(ev.dp, ev.dp) + dot(diff, ev.ddp);
    let step = select(f / df, 0.0, abs(df) < 1e-8);
    best_t = clamp(best_t - step, 0.0, 1.0);
  }

  return best_t;
}

fn initial_guess_closest_point(point: vec2f, curve: CubicBezier) -> f32 {
  let COARSE = 7u;
  var best_t = 0.0;
  var min_dist_sq = 1e30;

  for (var i = 0u; i <= COARSE; i++) {
    let t = f32(i) / f32(COARSE);
    let p = bezier_point(curve, t);
    let d = dot(p - point, p - point);
    if (d < min_dist_sq) {
      min_dist_sq = d;
      best_t = t;
    }
  }

  let step = 1.0 / f32(COARSE);
  var lo = max(0.0, best_t - step);
  var hi = min(1.0, best_t + step);

  for (var i = 0u; i < 5u; i++) {
    let third = (hi - lo) / 3.0;
    let m1 = lo + third;
    let m2 = hi - third;
    let p1 = bezier_point(curve, m1);
    let p2 = bezier_point(curve, m2);
    let d1 = dot(p1 - point, p1 - point);
    let d2 = dot(p2 - point, p2 - point);
    if (d1 < d2) { hi = m2; } else { lo = m1; }
  }

  return (lo + hi) * 0.5;
}

fn project_point_to_line_segment(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;

  let line_length_sq = dot(line_vec, line_vec);

  if (line_length_sq < 1e-8) {
    return 0.0;
  }

  let t = dot(point_vec, line_vec) / line_length_sq;
  return clamp(t, 0.0, 1.0);
}

fn distance_to_line_segment(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;

  let line_length_sq = dot(line_vec, line_vec);

  if (line_length_sq < 1e-8) {
    return length(point_vec);
  }

  let t = dot(point_vec, line_vec) / line_length_sq;

  if (t <= 0.0) {
    return length(point_vec);
  } else if (t >= 1.0) {
    return length(point - line_end);
  } else {
    let closest_point = line_start + t * line_vec;
    return length(point - closest_point);
  }
}

fn evaluate_shape(point: vec2f) -> f32 {
  var closest_curve_idx = 0u;
  var closest_t = 0.0;
  var min_distance: f32 = 1e+10;

  let num_curves = arrayLength(&curves) / 4;
  for (var i = 0u; i < num_curves; i++) {
    let curve = CubicBezier(
      curves[i * 4 + 0],
      curves[i * 4 + 1],
      curves[i * 4 + 2],
      curves[i * 4 + 3]
    );

    let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;

    if (is_straight_line) {
      let distance = distance_to_line_segment(point, curve.p0, curve.p3);
      if (distance < min_distance) {
        closest_curve_idx = i;
        closest_t = project_point_to_line_segment(point, curve.p0, curve.p3);
        min_distance = distance;
      }
    } else {
      let t = closest_point_on_bezier(point, curve);
      let closest_point = bezier_point(curve, t);
      let distance = length(point - closest_point);
      if (distance < min_distance) {
        closest_curve_idx = i;
        closest_t = t;
        min_distance = distance;
      }
    }
  }

  // Normalise t=1.0 to t=0.0 of the next-curve-in-the-same-path so that
  // (curve_idx + t) never reaches num_curves and stays consistent at junctions.
  if (closest_t >= 1.0) {
    let next_idx = (closest_curve_idx + 1u) % num_curves;
    let cur_p3   = curves[closest_curve_idx * 4u + 3u];
    let next_p0  = curves[next_idx * 4u + 0u];
    let bridge   = next_p0 - cur_p3;

    if (dot(bridge, bridge) < 1e-6) {
      closest_curve_idx = next_idx;
    } else {
      var i = closest_curve_idx;
      for (var k = 0u; k < num_curves; k = k + 1u) {
        let prev_i  = (i + num_curves - 1u) % num_curves;
        let prev_p3 = curves[prev_i * 4u + 3u];
        let i_p0    = curves[i * 4u + 0u];
        let gap     = prev_p3 - i_p0;
        if (dot(gap, gap) > 1e-6) { break; }
        i = prev_i;
      }
      closest_curve_idx = i;
    }
    closest_t = 0.0;
  }

  return f32(closest_curve_idx) + closest_t;
}
