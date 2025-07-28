
struct Uniforms {
  canvas_size: vec2f,
  num_curves: u32,
  stroke_width: f32,
};

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

struct Vertex {
  @location(0) position: vec2f,
  @location(1) color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var<storage, read> curves: array<CubicBezier>;
@group(0) @binding(2) var<uniform> canvas_matrix: mat4x4f;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) world_pos: vec2f,
  @location(1) color: vec4f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  var vsOut: VSOutput;
  
  let clip_space = canvas_matrix * vec4f(vert.position, 0.0, 1.0);
  vsOut.position = clip_space;
  vsOut.world_pos = vert.position;
  vsOut.color = vert.color;
  
  return vsOut;
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

// Calculate winding number contribution from a curve using adaptive quality
fn curve_winding_contribution(point: vec2f, curve: CubicBezier) -> f32 {
  // Use fwidth to determine appropriate subdivision level based on screen-space derivatives
  let screen_space_gradient = fwidth(point);
  let curve_size = max(
    distance(curve.p0, curve.p3),
    max(distance(curve.p0, curve.p1), distance(curve.p2, curve.p3))
  );
  
  // Adaptive step count based on curve complexity and screen resolution
  let base_steps = 4;
  let gradient_factor = length(screen_space_gradient);
  let adaptive_steps = i32(clamp(
    f32(base_steps) * (curve_size / max(gradient_factor, 0.1)),
    f32(base_steps),
    32.0
  ));
  
  var winding = 0.0;
  
  // Use Green's theorem for more accurate winding calculation
  for (var i = 0; i < adaptive_steps; i++) {
    let t1 = f32(i) / f32(adaptive_steps);
    let t2 = f32(i + 1) / f32(adaptive_steps);
    
    let p1 = bezier_point(curve, t1);
    let p2 = bezier_point(curve, t2);
    
    // Vector from query point to curve points
    let v1 = p1 - point;
    let v2 = p2 - point;
    
    // Skip if either point is very close to avoid numerical issues
    let dist1 = length(v1);
    let dist2 = length(v2);
    if (dist1 < 1e-6 || dist2 < 1e-6) {
      continue;
    }
    
    // Normalize vectors
    let n1 = v1 / dist1;
    let n2 = v2 / dist2;
    
    // Calculate signed angle using atan2 for better numerical stability
    let cross_prod = n1.x * n2.y - n1.y * n2.x;
    let dot_prod = dot(n1, n2);
    
    // Use atan2 for proper quadrant handling
    winding += atan2(cross_prod, dot_prod);
  }
  
  return winding / (2.0 * 3.14159);
}

struct ShapeInfo {
  signed_distance: f32,
  stroke_alpha: f32,
  fill_alpha: f32,
}

// Main shape evaluation function using SDF approach
fn evaluate_shape(point: vec2f) -> ShapeInfo {
  var min_distance = 1e10;
  var winding_number = 0.0;
  var t = 0.0;
  
  // For each curve, find closest point and accumulate winding
  for (var i = 0u; i < u.num_curves; i++) {
    let curve = curves[i];
    
    // Find closest point on this curve
    let closest_t = closest_point_on_bezier(point, curve);
    let closest_point = bezier_point(curve, closest_t);
    let distance = length(point - closest_point);

    if (min_distance > distance) {
      t = closest_t;
    }
    
    min_distance = min(min_distance, distance);
    
    // Calculate winding contribution for fill determination
    winding_number += curve_winding_contribution(point, curve);
  }
  
  // Determine if point is inside based on winding number
  let is_inside = abs(winding_number) > 0.5;
  let signed_dist = select(min_distance, -min_distance, is_inside);
  let pixel_gradient = fwidth(signed_dist);
  
  // Anti-aliased fill (negative distance = inside)
  let fill_alpha = smoothstep(pixel_gradient, -pixel_gradient, signed_dist);
  
  // Anti-aliased stroke (based on distance to curve boundary)
  let stroke_half_width = u.stroke_width * 0.5;
  let stroke_alpha = smoothstep(stroke_half_width + pixel_gradient, stroke_half_width - pixel_gradient, abs(signed_dist));
  return ShapeInfo(signed_dist, stroke_alpha, fill_alpha);
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  // Evaluate shape using SDF approach
  let shape_info = evaluate_shape(vsOut.world_pos);
  
  // Define fill and stroke colors
  let stroke_color = vec4f(0.0, 1.0, 0.0, 1.0); // Black stroke

  // Combine fill and stroke
  // If stroke is visible, use stroke color, otherwise use fill color
  let final_color = mix(vsOut.color, stroke_color, shape_info.stroke_alpha);
  
  // Final alpha is maximum of fill and stroke alpha
  let final_alpha = max(shape_info.fill_alpha, shape_info.stroke_alpha);
  return final_color * final_alpha;
}
