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

@compute @workgroup_size(1) fn cs(
  @builtin(global_invocation_id) id : vec3u
)  {
  let pos = vec2f(id.xy) + vec2f(0.5, 0.5);
  let shape_info = evaluate_shape(pos);

  textureStore(tex, id.xy, vec4f(
    shape_info.signed_distance,
    shape_info.t,
    shape_info.angle,
    1.0
  ));
}


// Evaluate cubic Bézier at parameter t
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

// First derivative of cubic Bézier
fn bezier_derivative(curve: CubicBezier, t: f32) -> vec2f {
  let one_minus_t = 1.0 - t;
  return 3.0 * one_minus_t * one_minus_t * (curve.p1 - curve.p0) +
         6.0 * t * one_minus_t * (curve.p2 - curve.p1) +
         3.0 * t * t * (curve.p3 - curve.p2);
}

// Second derivative of cubic Bézier
fn bezier_second_derivative(curve: CubicBezier, t: f32) -> vec2f {
  return 6.0 * (1.0 - t) * (curve.p2 - 2.0 * curve.p1 + curve.p0) +
         6.0 * t * (curve.p3 - 2.0 * curve.p2 + curve.p1);
}

// Find closest point on cubic Bézier curve to given point using analytical method
fn closest_point_on_bezier(point: vec2f, curve: CubicBezier) -> f32 {
  // At the closest point, (P(t) - point) ⊥ P'(t)
  // This gives us: dot(P(t) - point, P'(t)) = 0
  // We can solve this quintic equation analytically or use Newton-Raphson
  
  // Start with a good initial guess using the control polygon
  var best_t = initial_guess_closest_point(point, curve);
  // if there is any weird artifact in the middle of the shape, then it's most likely because of initial guess!
  
  // Newton-Raphson to find exact solution
  for (var i = 0; i < 5; i++) {
    let curve_point = bezier_point(curve, best_t);
    let derivative = bezier_derivative(curve, best_t);
    let second_derivative = bezier_second_derivative(curve, best_t);
    
    let diff = curve_point - point;
    
    // f(t) = dot(P(t) - point, P'(t)) = 0
    let f = dot(diff, derivative);
    
    // f'(t) = dot(P'(t), P'(t)) + dot(P(t) - point, P''(t))
    let df = dot(derivative, derivative) + dot(diff, second_derivative);
    
    if (abs(df) < 1e-8) { break; }
    
    var new_t = best_t - f / df;
    
    // Clamp to valid range
    new_t = clamp(new_t, 0.0, 1.0);
    
    if (abs(new_t - best_t) < 1e-8) { break; }
    best_t = new_t;
  }
  
  return best_t;
}

// Get initial guess for closest point using hierarchical sampling
fn initial_guess_closest_point(point: vec2f, curve: CubicBezier) -> f32 {
  // Stage 1: Coarse sampling to find approximate region
  var best_t = 0.0;
  var min_dist_sq = 1e10;
  
  let coarse_samples = 16; // More samples for better coverage
  for (var i = 0; i <= coarse_samples; i++) {
    let t = f32(i) / f32(coarse_samples);
    let curve_point = bezier_point(curve, t);
    let dist_sq = dot(curve_point - point, curve_point - point);
    
    if (dist_sq < min_dist_sq) {
      min_dist_sq = dist_sq;
      best_t = t;
    }
  }
  
  // Stage 2: Refine in the neighborhood of the best coarse sample
  let refine_range = 1.0 / f32(coarse_samples); // Search around ±one sample interval
  let t_min = max(0.0, best_t - refine_range);
  let t_max = min(1.0, best_t + refine_range);
  
  let fine_samples = 8;
  for (var i = 0; i <= fine_samples; i++) {
    let t = t_min + (t_max - t_min) * f32(i) / f32(fine_samples);
    let curve_point = bezier_point(curve, t);
    let dist_sq = dot(curve_point - point, curve_point - point);
    
    if (dist_sq < min_dist_sq) {
      min_dist_sq = dist_sq;
      best_t = t;
    }
  }
  
  return best_t;
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

// Ray casting: count intersections of horizontal ray with curve
fn ray_cast_curve_crossing(point: vec2f, curve: CubicBezier) -> i32 {
  // Quick Y-bounds check - if point is outside Y range, no intersection possible
  let y_min = min(min(curve.p0.y, curve.p1.y), min(curve.p2.y, curve.p3.y));
  let y_max = max(max(curve.p0.y, curve.p1.y), max(curve.p2.y, curve.p3.y));
  let x_min = max(max(curve.p0.x, curve.p1.x), max(curve.p2.x, curve.p3.x));
  
  if (point.y < y_min || point.y > y_max || point.x > x_min) {
    return 0;
  }
  
  // Sample the curve at regular intervals to find intersections
  var crossings = 0;
  let samples = 32; // Good balance between accuracy and performance
  
  for (var i = 0; i < samples; i++) {
    let t1 = f32(i) / f32(samples);
    let t2 = f32(i + 1) / f32(samples);
    
    let p1 = bezier_point(curve, t1);
    let p2 = bezier_point(curve, t2);
    
    // Check if this segment crosses the horizontal ray
    if (ray_crosses_segment(point, p1, p2)) {
      // Calculate the actual intersection X coordinate
      let intersection_x = get_ray_intersection_x(point.y, p1, p2);
      
      // Only count if intersection is to the right of the point
      if (intersection_x > point.x) {
        // Determine crossing direction for proper winding
        if (p1.y < point.y && p2.y >= point.y) {
          crossings += 1; // Upward crossing
        } else if (p1.y >= point.y && p2.y < point.y) {
          crossings -= 1; // Downward crossing
        }
      }
    }
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
    // let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD && curve.p2.x > STRAIGHT_LINE_THRESHOLD;


    if (is_straight_line) {
      // Handle as straight line from p0 to p3
      // if (u.stroke_width >= EPSILON) {
        let distance = distance_to_line_segment(point, curve.p0, curve.p3);
      // }
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

      // if (u.stroke_width >= EPSILON) {
        let t = closest_point_on_bezier(point, curve);
        let closest_point = bezier_point(curve, t);
        let distance = length(point - closest_point);
        if (distance < min_distance) {
          closest_curve_idx = i;
          closest_t = t;
          min_distance = distance;
        }
      // }
      
      // Ray casting for curve
      total_crossings += ray_cast_curve_crossing(point, curve);
    }
    
    // min_distance = min(min_distance, distance);
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
  // Count total crossings and check if odd
  let crossing_count = abs(total_crossings);
  let is_inside = (crossing_count % 2) == 1;
  let signed_dist = select(-min_distance, min_distance, is_inside);
  // let pixel_gradient = fwidth(signed_dist);
  
  // Anti-aliased fill (negative distance = inside)
  // let fill_alpha = smoothstep(pixel_gradient, -pixel_gradient, signed_dist);
  
  // Anti-aliased stroke (based on distance to curve boundary)
  // let stroke_half_width = u.stroke_width * 0.5;
  // let stroke_alpha = smoothstep(stroke_half_width + pixel_gradient, stroke_half_width - pixel_gradient, abs(signed_dist));
  return ShapeInfo(signed_dist, f32(closest_curve_idx) + closest_t, angle);
}