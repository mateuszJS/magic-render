struct Vertex {
  @location(0) position: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) originalPosition: vec2f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var<storage, read> quadBezierCurves: array<array<vec2f, 4>>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  out.position = u.worldViewProjection * vert.position;
  out.originalPosition = vert.position.xy;
  return out;
}

const WHITE = 7u; // 111
const MAGENTA = 5u; // 101
const YELLOW = 6u; // 110
const CYAN = 3u; // 011

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  var minDistance = 1000.0;
  var minI: u32 = 0;
  var minT: u32 = 0;
  let curvesCount = arrayLength(&quadBezierCurves);

  // Calculate signed distance using winding number
  // For each curve, check if the fragment point is inside or outside
  var windingNumber = 0.0;
  // var color = if (curvesCount == 1) { WHITE } else { MAGENTA };
  
  for (var i: u32 = 0; i < curvesCount; i++) {
    let curve_p0 = quadBezierCurves[i][0];
    let curve_p1 = quadBezierCurves[i][1];
    let curve_p2 = quadBezierCurves[i][2];
    let curve_p3 = quadBezierCurves[i][3];
    
    // Sample the curve and calculate winding contribution
    let curve_samples = 16u;
    for (var j: u32 = 0; j < curve_samples; j++) {
      let t1 = f32(j) / f32(curve_samples);
      let t2 = f32(j + 1u) / f32(curve_samples);
      
      // Calculate points on curve
      let one_minus_t1 = 1.0 - t1;
      let one_minus_t1_2 = one_minus_t1 * one_minus_t1;
      let one_minus_t1_3 = one_minus_t1_2 * one_minus_t1;
      let t1_2 = t1 * t1;
      let t1_3 = t1_2 * t1;
      
      let point1 = one_minus_t1_3 * curve_p0 + 
                   3.0 * one_minus_t1_2 * t1 * curve_p1 + 
                   3.0 * one_minus_t1 * t1_2 * curve_p2 + 
                   t1_3 * curve_p3;
      
      let one_minus_t2 = 1.0 - t2;
      let one_minus_t2_2 = one_minus_t2 * one_minus_t2;
      let one_minus_t2_3 = one_minus_t2_2 * one_minus_t2;
      let t2_2 = t2 * t2;
      let t2_3 = t2_2 * t2;
      
      let point2 = one_minus_t2_3 * curve_p0 + 
                   3.0 * one_minus_t2_2 * t2 * curve_p1 + 
                   3.0 * one_minus_t2 * t2_2 * curve_p2 + 
                   t2_3 * curve_p3;
      
      // Calculate winding contribution for this segment
      let v1 = point1 - in.originalPosition;
      let v2 = point2 - in.originalPosition;
      
      // Check if segment crosses the positive x-axis from our point
      if ((v1.y <= 0.0 && v2.y > 0.0) || (v1.y > 0.0 && v2.y <= 0.0)) {
        // Calculate intersection with x-axis
        let t_intersect = -v1.y / (v2.y - v1.y);
        let x_intersect = v1.x + t_intersect * (v2.x - v1.x);
        
        if (x_intersect > 0.0) {
          if (v2.y > v1.y) {
            windingNumber += 1.0;
          } else {
            windingNumber -= 1.0;
          }
        }
      }

      let distanceToPoint = distance(point1, in.originalPosition);
      if (distanceToPoint < minDistance) {
        minDistance = distanceToPoint;
      }
    }


    // calculating color for the next edge
    // if (color == YELLOW) {
    //   color = CYAN;
    // }
    // color = YELLOW;
  }
  
  // Determine sign: inside if winding number is non-zero, outside if zero
  let sign = select(-1.0, 1.0, abs(windingNumber) > 0.5);
  let signedDistance = sign * minDistance;

  return vec4f(
    (f32(minI) / f32(curvesCount)),
    0.0,
    signedDistance / 5.0,
    // direction.x * 0.5 + 0.5, // Map from [-1,1] to [0,1] for visualization
    // direction.y * 0.5 + 0.5, // Map from [-1,1] to [0,1] for visualization
    1.0
  );
}
