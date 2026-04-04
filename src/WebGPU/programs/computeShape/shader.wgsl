const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

@group(0) @binding(0) var tex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(1) var<storage, read> curves: array<vec2f>;

@compute @workgroup_size($WORKING_GROUP_SIZE) fn cs(
  @builtin(global_invocation_id) id : vec3u
)  {
  let size = textureDimensions(tex);
  if (id.x >= size.x || id.y >= size.y) {return;}

  let pos = vec2f(id.xy) + vec2f(0.5, 0.5);
  let shape_info = evaluate_shape(pos);

  textureStore(tex, id.xy, vec4f(
    shape_info.signed_distance,
    shape_info.t,
    shape_info.angle,
    1.0
  ));
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
// ~50% fewer arithmetic ops vs evaluating each separately.
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
  // if there is any weird artifact in the middle of the shape, then it's most likely because of initial guess!

  // Fixed 4 iterations — no early-exit branches so all GPU threads stay in lockstep.
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

// Divide-and-conquer initial guess:
//   Phase 1 — 8 coarse uniform samples to identify the best interval.
//   Phase 2 — 5 ternary-search iterations within that interval.
// Total: 8 + 10 = 18 bezier_point calls  vs  17+9 = 26 in the previous version.
// Ternary search is guaranteed to find the minimum if the function is unimodal on
// the identified interval, which is the common case for Bézier closest-point queries.
fn initial_guess_closest_point(point: vec2f, curve: CubicBezier) -> f32 {
  // Phase 1: coarse uniform scan
  let COARSE = 7u; // 8 samples: t = 0, 1/7, ..., 1
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

  // Phase 2: ternary search within ±one coarse step of best_t
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

// Project point onto line segment and return parameter [0,1]
fn project_point_to_line_segment(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;

  let line_length_sq = dot(line_vec, line_vec);

  if (line_length_sq < 1e-8) {
    return 0.0; // Degenerate line
  }

  let t = dot(point_vec, line_vec) / line_length_sq;
  return clamp(t, 0.0, 1.0);
}

// Calculate distance from point to line segment
fn distance_to_line_segment(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;

  let line_length_sq = dot(line_vec, line_vec);

  if (line_length_sq < 1e-8) {
    // Degenerate line - distance to start point
    return length(point_vec);
  }

  let t = dot(point_vec, line_vec) / line_length_sq;

  if (t <= 0.0) {
    // Closest point is the start of the line segment
    return length(point_vec);
  } else if (t >= 1.0) {
    // Closest point is the end of the line segment
    return length(point - line_end);
  } else {
    // Closest point is on the line segment
    let closest_point = line_start + t * line_vec;
    return length(point - closest_point);
  }
}

// Calculate winding number contribution from a line segment
fn line_winding_contribution(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  // Vector from query point to line endpoints
  let v1 = line_start - point;
  let v2 = line_end - point;

  // Skip if either point is very close to avoid numerical issues
  let dist1 = length(v1);
  let dist2 = length(v2);
  if (dist1 < 1e-6 || dist2 < 1e-6) {
    return 0.0;
  }

  // Normalize vectors
  let n1 = v1 / dist1;
  let n2 = v2 / dist2;

  // Calculate signed angle using atan2 for proper quadrant handling
  let cross_prod = n1.x * n2.y - n1.y * n2.x;
  let dot_prod = dot(n1, n2);

  // Use atan2 for proper quadrant handling
  let angle = atan2(cross_prod, dot_prod);

  return angle / (2.0 * 3.14159);
}

// Ray casting: count intersections of horizontal ray with curve.
// Reuses the previous sample as the left endpoint of each segment — cuts
// bezier_point calls from 2×N to N+1 (64 → 17 with N=16).
fn ray_cast_curve_crossing(point: vec2f, curve: CubicBezier) -> i32 {
  let y_min = min(min(curve.p0.y, curve.p1.y), min(curve.p2.y, curve.p3.y));
  let y_max = max(max(curve.p0.y, curve.p1.y), max(curve.p2.y, curve.p3.y));
  let x_min = max(max(curve.p0.x, curve.p1.x), max(curve.p2.x, curve.p3.x));

  if (point.y < y_min || point.y > y_max || point.x > x_min) {
    return 0;
  }

  let samples = 16u;
  var crossings = 0;
  var p_prev = bezier_point(curve, 0.0);

  for (var i = 0u; i < samples; i++) {
    let t_next = f32(i + 1u) / f32(samples);
    let p_next = bezier_point(curve, t_next);

    if (ray_crosses_segment(point, p_prev, p_next)) {
      let intersection_x = get_ray_intersection_x(point.y, p_prev, p_next);
      if (intersection_x > point.x) {
        if (p_prev.y < point.y && p_next.y >= point.y) {
          crossings += 1;
        } else if (p_prev.y >= point.y && p_next.y < point.y) {
          crossings -= 1;
        }
      }
    }

    p_prev = p_next;
  }

  return crossings;
}

// Check if horizontal ray from point crosses the line segment
fn ray_crosses_segment(point: vec2f, p1: vec2f, p2: vec2f) -> bool {
  // Check if the segment crosses the horizontal line at point.y
  return (p1.y < point.y && p2.y >= point.y) || (p1.y >= point.y && p2.y < point.y);
}

// Calculate X coordinate where horizontal ray intersects line segment
fn get_ray_intersection_x(ray_y: f32, p1: vec2f, p2: vec2f) -> f32 {
  if (abs(p2.y - p1.y) < 1e-8) {
    // Horizontal line - return leftmost X
    return min(p1.x, p2.x);
  }

  // Linear interpolation to find intersection X
  let t = (ray_y - p1.y) / (p2.y - p1.y);
  return p1.x + t * (p2.x - p1.x);
}

// Helper function: distance from point to line (for flatness test)
fn distance_point_to_line(point: vec2f, line_start: vec2f, line_end: vec2f) -> f32 {
  let line_vec = line_end - line_start;
  let point_vec = point - line_start;

  let line_length_sq = dot(line_vec, line_vec);
  if (line_length_sq < 1e-8) {
    return length(point_vec);
  }

  let t = dot(point_vec, line_vec) / line_length_sq;
  let closest = line_start + clamp(t, 0.0, 1.0) * line_vec;
  return length(point - closest);
}

struct ShapeInfo {
  signed_distance: f32,
  t: f32,
  angle: f32
}

// Main shape evaluation function using SDF approach with ray casting
fn evaluate_shape(point: vec2f) -> ShapeInfo {
  var total_crossings: i32 = 0;
  var closest_curve_idx = 0u;
  var closest_t = 0.0;
  var min_distance: f32 = 1e+10;

  // For each curve, find closest point and count ray crossings
  let num_curves = arrayLength(&curves) / 4;
  for (var i = 0u; i < num_curves; i++) {
    let curve = CubicBezier(
      curves[i * 4 + 0],
      curves[i * 4 + 1],
      curves[i * 4 + 2],
      curves[i * 4 + 3]
    );

    // Check if this is a straight line,
    // we could check also p2, but at this point we should receive only
    // straight line on both handles, not a case for just one straight handle,
    // those are changed to have sibling cp value
    let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;

    if (is_straight_line) {
      // Handle as straight line from p0 to p3
      let distance = distance_to_line_segment(point, curve.p0, curve.p3);
      if (distance < min_distance) {
        closest_curve_idx = i;
        closest_t = project_point_to_line_segment(point, curve.p0, curve.p3);
        min_distance = distance;
      }

      // Simple ray casting for line segment
      if (ray_crosses_segment(point, curve.p0, curve.p3)) {
        let intersection_x = get_ray_intersection_x(point.y, curve.p0, curve.p3);
        if (intersection_x > point.x) {
          if (curve.p0.y < point.y && curve.p3.y >= point.y) {
            total_crossings += 1; // Upward crossing
          } else if (curve.p0.y >= point.y && curve.p3.y < point.y) {
            total_crossings -= 1; // Downward crossing
          }
        }
      }
    } else {
      // Handle as normal cubic Bézier curve
      let t = closest_point_on_bezier(point, curve);
      let closest_point = bezier_point(curve, t);
      let distance = length(point - closest_point);
      if (distance < min_distance) {
        closest_curve_idx = i;
        closest_t = t;
        min_distance = distance;
      }

      // Ray casting for curve
      total_crossings += ray_cast_curve_crossing(point, curve);
    }
  }

  var curve = CubicBezier(
    curves[closest_curve_idx * 4 + 0],
    curves[closest_curve_idx * 4 + 1],
    curves[closest_curve_idx * 4 + 2],
    curves[closest_curve_idx * 4 + 3]
  );

  // handling straight line case
  if (curve.p1.x > STRAIGHT_LINE_THRESHOLD) {
    curve.p1 = curve.p0;
    curve.p2 = curve.p3;
  }

  let closest_point = bezier_point(curve, closest_t);
  let angle = PI + atan2(point.y - closest_point.y, point.x - closest_point.x);

  // Determine if point is inside using odd-even rule (ray casting)
  let crossing_count = abs(total_crossings);
  let is_inside = (crossing_count % 2) == 1;

  // if you would like to use non zero rule, uncomment below
  // let is_inside = total_crossings != 0;

  let signed_dist = select(-min_distance, min_distance, is_inside);

  return ShapeInfo(signed_dist, f32(closest_curve_idx) + closest_t, angle);
}
