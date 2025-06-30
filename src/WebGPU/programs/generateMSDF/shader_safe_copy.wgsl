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
  out.originalPosition = vert.position.xy + vec2f(0.5);
  return out;
}

const WHITE = 7u; // 111
const MAGENTA = 5u; // 101
const YELLOW = 6u; // 110
const CYAN = 3u; // 011

const RED = 1u; // 001
const GREEN = 2u; // 010
const BLUE = 4u; // 100

fn median(a: f32, b: f32, c: f32) -> f32 {
  if ((a < b && b < c) || (c < b && b < a)) {
    return b;
  } else if ((b < a && a < c) || (c < a && a < b)) {
    return a;
  } else {
    return c;
  }
}

fn signedPseudoDistance(pixelPos: vec2f, curveIndex: u32) -> f32 {
  let p0 = quadBezierCurves[curveIndex][0];
  let p1 = quadBezierCurves[curveIndex][1];
  let p2 = quadBezierCurves[curveIndex][2];
  let p3 = quadBezierCurves[curveIndex][3];
  
  var minDistance = 1000.0;
  var bestT = 0.0;
  
  // Sample the curve with extended range for pseudo-distance
  // We extend beyond [0,1] to include the infinite extensions
  let samples = 64u;
  let tStart = -0.5; // Start before curve begins
  let tEnd = 1.5;    // End after curve ends
  
  for (var i: u32 = 0; i <= samples; i++) {
    let t = tStart + (tEnd - tStart) * f32(i) / f32(samples);
    
    var pointOnCurve: vec2f;
    
    if (t >= 0.0 && t <= 1.0) {
      // Standard cubic bezier evaluation for t in [0,1]
      let one_minus_t = 1.0 - t;
      let one_minus_t2 = one_minus_t * one_minus_t;
      let one_minus_t3 = one_minus_t2 * one_minus_t;
      let t2 = t * t;
      let t3 = t2 * t;
      
      pointOnCurve = one_minus_t3 * p0 + 
                     3.0 * one_minus_t2 * t * p1 + 
                     3.0 * one_minus_t * t2 * p2 + 
                     t3 * p3;
    } else {
      // Linear extension beyond the curve endpoints
      if (t < 0.0) {
        // Extension from start point (p0) using tangent at t=0
        let tangentAtStart = 3.0 * (p1 - p0);
        if (length(tangentAtStart) > 0.001) {
          pointOnCurve = p0 + t * normalize(tangentAtStart) * length(tangentAtStart);
        } else {
          // Fallback: use direction to p2 if p1 is too close to p0
          let fallbackTangent = p2 - p0;
          if (length(fallbackTangent) > 0.001) {
            pointOnCurve = p0 + t * normalize(fallbackTangent) * length(fallbackTangent);
          } else {
            pointOnCurve = p0; // Degenerate case
          }
        }
      } else {
        // Extension from end point (p3) using tangent at t=1
        let tangentAtEnd = 3.0 * (p3 - p2);
        if (length(tangentAtEnd) > 0.001) {
          pointOnCurve = p3 + (t - 1.0) * normalize(tangentAtEnd) * length(tangentAtEnd);
        } else {
          // Fallback: use direction from p1 if p2 is too close to p3
          let fallbackTangent = p3 - p1;
          if (length(fallbackTangent) > 0.001) {
            pointOnCurve = p3 + (t - 1.0) * normalize(fallbackTangent) * length(fallbackTangent);
          } else {
            pointOnCurve = p3; // Degenerate case
          }
        }
      }
    }
    
    let dist = distance(pointOnCurve, pixelPos);
    if (dist < minDistance) {
      minDistance = dist;
      bestT = t;
    }
  }
  
  // Calculate winding number to determine sign
  var windingNumber = 0.0;
  let windingSamples = 16u;
  
  for (var j: u32 = 0; j < windingSamples; j++) {
    let t1 = f32(j) / f32(windingSamples);
    let t2 = f32(j + 1u) / f32(windingSamples);
    
    // Evaluate curve at t1 and t2
    let one_minus_t1 = 1.0 - t1;
    let one_minus_t1_2 = one_minus_t1 * one_minus_t1;
    let one_minus_t1_3 = one_minus_t1_2 * one_minus_t1;
    let t1_2 = t1 * t1;
    let t1_3 = t1_2 * t1;
    
    let point1 = one_minus_t1_3 * p0 + 
                 3.0 * one_minus_t1_2 * t1 * p1 + 
                 3.0 * one_minus_t1 * t1_2 * p2 + 
                 t1_3 * p3;
    
    let one_minus_t2 = 1.0 - t2;
    let one_minus_t2_2 = one_minus_t2 * one_minus_t2;
    let one_minus_t2_3 = one_minus_t2_2 * one_minus_t2;
    let t2_2 = t2 * t2;
    let t2_3 = t2_2 * t2;
    
    let point2 = one_minus_t2_3 * p0 + 
                 3.0 * one_minus_t2_2 * t2 * p1 + 
                 3.0 * one_minus_t2 * t2_2 * p2 + 
                 t2_3 * p3;
    
    // Calculate winding contribution
    let v1 = point1 - pixelPos;
    let v2 = point2 - pixelPos;
    
    if ((v1.y <= 0.0 && v2.y > 0.0) || (v1.y > 0.0 && v2.y <= 0.0)) {
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
  }
  
  // Determine sign: inside if winding number is non-zero, outside if zero
  let sign = select(-1.0, 1.0, abs(windingNumber) > 0.5);
  return sign * minDistance;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  var minDistance = 1000.0;
  let curvesCount = arrayLength(&quadBezierCurves);

  var windingNumber = 0.0;
  
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
      // Determine sign: inside if winding number is non-zero, outside if zero
      let sign = select(-1.0, 1.0, abs(windingNumber) > 0.5);
      let signedDistance = sign * distanceToPoint;

      if (distanceToPoint < abs(minDistance)) {
        minDistance = signedDistance;
        // minRedEdge = i;
      }
    }
  }
  minDistance /= 10.0;
  // minDistance += 0.5;
  // minDistance = abs(minDistance);
  // minDistance = abs(minDistance);
  return vec4f(minDistance, minDistance, minDistance, 1.0);
}

@fragment fn safe_copy_fs(in: VertexOutput) -> @location(0) vec4f {
  var minRedDistance = 1000.0;
  var minGreenDistance = 1000.0;
  var minBlueDistance = 1000.0;

  var minRedEdge = 0u;
  var minGreenEdge = 0u;
  var minBlueEdge = 0u;

  let curvesCount = arrayLength(&quadBezierCurves);

  // Calculate signed distance using winding number
  // For each curve, check if the fragment point is inside or outside
  var windingNumber = 0.0;
  var color = MAGENTA;
  if (curvesCount == 1) {
    color = WHITE;
  };
  
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
      // Determine sign: inside if winding number is non-zero, outside if zero
      let sign = select(-1.0, 1.0, abs(windingNumber) > 0.5);
      let signedDistance = sign * distanceToPoint;

      // if (distanceToPoint < minRedDistance) {
      //   minRedDistance = distanceToPoint;
      //   minRedEdge = i;
      // }

      // if (signedDistance < minRedDistance) {
      if ((color & RED) > 0 && abs(signedDistance) < abs(minRedDistance)) {
        minRedDistance = signedDistance;
        minRedEdge = i;
      }
      if (abs(signedDistance) < abs(minGreenDistance)) {
      // if ((color & GREEN) > 0 && abs(signedDistance) < abs(minGreenDistance)) {
        minGreenDistance = signedDistance;
        minGreenEdge = i;
      }
      if ((color & BLUE) > 0 && abs(signedDistance) < abs(minBlueDistance)) {
        minBlueDistance = signedDistance;
        minBlueEdge = i;
      }
    }

    // minRedDistance = signedPseudoDistance(in.originalPosition, minRedEdge);
    // minGreenDistance = signedPseudoDistance(in.originalPosition, minGreenEdge);
    // minBlueDistance = signedPseudoDistance(in.originalPosition, minBlueEdge);


    // calculating color for the next edge
    if (color == YELLOW) {
      color = CYAN;
    } else {
      color = YELLOW;
    }
  }
  // minGreenDistance /= 100.0;
  if (minGreenDistance < 0.0) {
    minGreenDistance = 0.0;
  } else {
    minGreenDistance = 1.0;
  }
  // minGreenDistance = abs(minGreenDistance);
  return vec4f(minGreenDistance, minGreenDistance, minGreenDistance, 1.0);
  // return vec4f(minRedDistance + 0.5, minGreenDistance + 0.5, minBlueDistance + 0.5, 1.0);

  // let msdf = vec4f(minRedDistance, minGreenDistance, minBlueDistance, 1.0);
  // let d = median(minRedDistance, minGreenDistance, minBlueDistance) - 0.5;
  // return vec4f(d, d, d, 1.0);
}

// the author marked above approach as legacy
// https://github.com/Chlumsky/msdfgen/blob/master/core/msdfgen.cpp#L220