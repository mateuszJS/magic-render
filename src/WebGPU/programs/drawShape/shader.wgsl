struct Uniforms {
  canvas_size: vec2f,
  num_curves: u32,
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

// Solve cubic equation ax³ + bx² + cx + d = 0 analytically
fn solve_cubic(a: f32, b: f32, c: f32, d: f32) -> array<f32, 3> {
  var roots: array<f32, 3>;
  var num_roots = 0;
  
  let epsilon = 1e-6;
  
  if (abs(a) < epsilon) {
    // Quadratic case: bx² + cx + d = 0
    if (abs(b) < epsilon) {
      // Linear case: cx + d = 0
      if (abs(c) > epsilon) {
        roots[0] = -d / c;
        num_roots = 1;
      }
    } else {
      let discriminant = c * c - 4.0 * b * d;
      if (discriminant >= 0.0) {
        let sqrt_disc = sqrt(discriminant);
        roots[0] = (-c + sqrt_disc) / (2.0 * b);
        roots[1] = (-c - sqrt_disc) / (2.0 * b);
        num_roots = 2;
      }
    }
  } else {
    // True cubic case - use Cardano's method
    let p = (3.0 * a * c - b * b) / (3.0 * a * a);
    let q = (2.0 * b * b * b - 9.0 * a * b * c + 27.0 * a * a * d) / (27.0 * a * a * a);
    
    let discriminant = (q * q / 4.0) + (p * p * p / 27.0);
    
    if (discriminant > epsilon) {
      // One real root
      let sqrt_disc = sqrt(discriminant);
      let u = pow(-q / 2.0 + sqrt_disc, 1.0 / 3.0);
      let v = pow(-q / 2.0 - sqrt_disc, 1.0 / 3.0);
      roots[0] = u + v - b / (3.0 * a);
      num_roots = 1;
    } else if (abs(discriminant) < epsilon) {
      // Two or three real roots (repeated)
      if (abs(q) < epsilon) {
        // Triple root
        roots[0] = -b / (3.0 * a);
        num_roots = 1;
      } else {
        // One single + one double root
        roots[0] = 3.0 * q / p - b / (3.0 * a);
        roots[1] = -3.0 * q / (2.0 * p) - b / (3.0 * a);
        num_roots = 2;
      }
    } else {
      // Three distinct real roots - use trigonometric solution
      let rho = sqrt(-p * p * p / 27.0);
      let theta = acos(-q / (2.0 * rho));
      let cube_root_rho = pow(rho, 1.0 / 3.0);
      
      roots[0] = 2.0 * cube_root_rho * cos(theta / 3.0) - b / (3.0 * a);
      roots[1] = 2.0 * cube_root_rho * cos((theta + 2.0 * 3.14159) / 3.0) - b / (3.0 * a);
      roots[2] = 2.0 * cube_root_rho * cos((theta + 4.0 * 3.14159) / 3.0) - b / (3.0 * a);
      num_roots = 3;
    }
  }
  
  // Mark unused roots with invalid values
  for (var i = num_roots; i < 3; i++) {
    roots[i] = -999.0; // Invalid marker
  }
  
  return roots;
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

// Ray-curve intersection for cubic Bézier using analytical solution
fn ray_intersects_cubic_bezier(ray_origin: vec2f, curve: CubicBezier) -> u32 {
  // Quick bounding box test
  let min_y = min(min(curve.p0.y, curve.p1.y), min(curve.p2.y, curve.p3.y));
  let max_y = max(max(curve.p0.y, curve.p1.y), max(curve.p2.y, curve.p3.y));
  
  if (ray_origin.y < min_y || ray_origin.y > max_y) {
    return 0u;
  }
  
  // Convert to parametric form: y(t) = at³ + bt² + ct + d
  let a = -curve.p0.y + 3.0 * curve.p1.y - 3.0 * curve.p2.y + curve.p3.y;
  let b = 3.0 * curve.p0.y - 6.0 * curve.p1.y + 3.0 * curve.p2.y;
  let c = -3.0 * curve.p0.y + 3.0 * curve.p1.y;
  let d = curve.p0.y - ray_origin.y;
  
  // Solve cubic equation analytically
  let roots = solve_cubic(a, b, c, d);
  
  var intersections = 0u;
  
  // Check each root
  for (var i = 0; i < 3; i++) {
    let t = roots[i];
    
    // Check if root is valid and in range [0, 1]
    if (t >= 0.0 && t <= 1.0 && t != -999.0) {
      // Calculate x coordinate at this t value
      let point = bezier_point(curve, t);
      
      // Check if intersection is to the right of ray origin
      if (point.x > ray_origin.x) {
        intersections += 1u;
      }
    }
  }
  
  return intersections;
}

fn point_in_shape(point: vec2f) -> bool {
  var intersections = 0u;
  
  for (var i = 0u; i < u.num_curves; i++) {
    intersections += ray_intersects_cubic_bezier(point, curves[i]);
  }
  
  return (intersections % 2u) == 1u;
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  // Multi-sampling for anti-aliasing
  var coverage = 0.0;
  let samples = 4; // 2x2 multisampling

      if (point_in_shape( vsOut.world_pos)) {
        coverage = 1.0;
      }

  // for (var x = 0; x < 2; x++) {
  //   for (var y = 0; y < 2; y++) {
  //     let offset = vec2f(f32(x) - 0.5, f32(y) - 0.5) * 0.5;
  //     let sample_pos = vsOut.world_pos + offset;
      
  //     if (point_in_shape(sample_pos)) {
  //       coverage += 0.25;
  //     }
  //   }
  // }
  
  return vec4f(vsOut.color.rgb, vsOut.color.a * coverage);
}
