const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;

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
  let pos = vsOut.position.xy;
  let shape_info = evaluate_shape(pos);
  return shape_info.signed_t;
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

struct BezierEval {
  p: vec2f,
  dp: vec2f,
  ddp: vec2f,
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
  if (line_length_sq < 1e-8) { return 0.0; }
  return clamp(dot(point_vec, line_vec) / line_length_sq, 0.0, 1.0);
}

fn distance_to_line_segment(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;
  let line_length_sq = dot(line_vec, line_vec);
  if (line_length_sq < 1e-8) { return length(point_vec); }
  let t = dot(point_vec, line_vec) / line_length_sq;
  if (t <= 0.0) { return length(point_vec); }
  if (t >= 1.0) { return length(point - line_end); }
  return length(point - (line_start + t * line_vec));
}

fn ray_cast_curve_crossing(point: vec2f, curve: CubicBezier) -> i32 {
  let y_min = min(min(curve.p0.y, curve.p1.y), min(curve.p2.y, curve.p3.y));
  let y_max = max(max(curve.p0.y, curve.p1.y), max(curve.p2.y, curve.p3.y));
  let x_min = max(max(curve.p0.x, curve.p1.x), max(curve.p2.x, curve.p3.x));

  if (point.y < y_min || point.y > y_max || point.x > x_min) { return 0; }

  let samples = 16u;
  var crossings = 0;
  var p_prev = bezier_point(curve, 0.0);

  for (var i = 0u; i < samples; i++) {
    let t_next = f32(i + 1u) / f32(samples);
    let p_next = bezier_point(curve, t_next);
    if (ray_crosses_segment(point, p_prev, p_next)) {
      let intersection_x = get_ray_intersection_x(point.y, p_prev, p_next);
      if (intersection_x > point.x) {
        if (p_prev.y < point.y && p_next.y >= point.y) { crossings += 1; }
        else if (p_prev.y >= point.y && p_next.y < point.y) { crossings -= 1; }
      }
    }
    p_prev = p_next;
  }

  return crossings;
}

fn ray_crosses_segment(point: vec2f, p1: vec2f, p2: vec2f) -> bool {
  return (p1.y < point.y && p2.y >= point.y) || (p1.y >= point.y && p2.y < point.y);
}

fn get_ray_intersection_x(ray_y: f32, p1: vec2f, p2: vec2f) -> f32 {
  if (abs(p2.y - p1.y) < 1e-8) { return min(p1.x, p2.x); }
  let t = (ray_y - p1.y) / (p2.y - p1.y);
  return p1.x + t * (p2.x - p1.x);
}

struct ShapeInfo {
  signed_t: f32,
}

fn evaluate_shape(point: vec2f) -> ShapeInfo {
  var total_crossings: i32 = 0;
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
      if (ray_crosses_segment(point, curve.p0, curve.p3)) {
        let intersection_x = get_ray_intersection_x(point.y, curve.p0, curve.p3);
        if (intersection_x > point.x) {
          if (curve.p0.y < point.y && curve.p3.y >= point.y) { total_crossings += 1; }
          else if (curve.p0.y >= point.y && curve.p3.y < point.y) { total_crossings -= 1; }
        }
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
      total_crossings += ray_cast_curve_crossing(point, curve);
    }
  }

  let is_inside = (abs(total_crossings) % 2) == 1;

  let t = f32(closest_curve_idx) + closest_t + 1.0;
  let signed_t = select(-t, t, is_inside);

  return ShapeInfo(signed_t);
}
