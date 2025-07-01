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
@group(0) @binding(1) var<storage, read> quadBezierCurves: array<array<vec2f, 5>>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  out.position = u.worldViewProjection * vert.position;
  out.originalPosition = vert.position.xy + vec2f(0.5);
  return out;
}

// Branchless median of three numbers
fn median(a: f32, b: f32, c: f32) -> f32 {
  return max(min(a, b), min(max(a, b), c));
}

// Evaluates a cubic Bézier curve at parameter t
fn evalBezier(p0: vec2f, p1: vec2f, p2: vec2f, p3: vec2f, t: f32) -> vec2f {
    let t2 = t * t;
    let t3 = t2 * t;
    let mt = 1.0 - t;
    let mt2 = mt * mt;
    let mt3 = mt2 * mt;
    return p0 * mt3 + 3.0 * p1 * mt2 * t + 3.0 * p2 * mt * t2 + p3 * t3;
}

// Evaluates the derivative of a cubic Bézier curve at parameter t
fn evalBezierDerivative(p0: vec2f, p1: vec2f, p2: vec2f, p3: vec2f, t: f32) -> vec2f {
    let t2 = t * t;
    let mt = 1.0 - t;
    let mt2 = mt * mt;
    return 3.0 * mt2 * (p1 - p0) + 6.0 * mt * t * (p2 - p1) + 3.0 * t2 * (p3 - p2);
}

// A robust and reasonably accurate pseudo-distance calculation for a cubic Bézier curve.
fn pseudoDistance(pixelPos: vec2f, curveIndex: u32) -> f32 {
  let p0 = quadBezierCurves[curveIndex][0];
  let p1 = quadBezierCurves[curveIndex][1];
  let p2 = quadBezierCurves[curveIndex][2];
  let p3 = quadBezierCurves[curveIndex][3];

  var closestT = 0.5; // Initial guess for the parameter t

  // Iteratively find the value of t on the infinite curve that is closest to the pixel.
  // This is a simplified Newton's method. 5 iterations are a good balance.
  for (var i = 0; i < 5; i = i + 1) {
    let pointOnCurve = evalBezier(p0, p1, p2, p3, closestT);
    let derivative = evalBezierDerivative(p0, p1, p2, p3, closestT);
    let vecToPixel = pixelPos - pointOnCurve;
    
    let dotProduct = dot(vecToPixel, derivative);
    let derivativeLengthSq = dot(derivative, derivative);

    // Adjust t towards the closest point. Do not clamp here.
    if (derivativeLengthSq > 1e-6) {
        closestT = closestT + dotProduct / derivativeLengthSq;
    }
  }

  // If the closest point on the infinite curve is within the segment [0, 1],
  // the distance is to that point. Otherwise, the pseudo-distance is the
  // distance to the closer of the two endpoints. This is a robust simplification.
  if (closestT > 0.0 && closestT < 1.0) {
    return distance(pixelPos, evalBezier(p0, p1, p2, p3, closestT));
  } else {
    let distToEndpoint0 = distance(pixelPos, p0);
    let distToEndpoint3 = distance(pixelPos, p3);
    return min(distToEndpoint0, distToEndpoint3);
  }
}

// Calculates the winding number contribution of a single curve.
// This determines how much a curve wraps around a point.
fn windingContribution(pixelPos: vec2f, curveIndex: u32) -> f32 {
    let p0 = quadBezierCurves[curveIndex][0];
    let p1 = quadBezierCurves[curveIndex][1];
    let p2 = quadBezierCurves[curveIndex][2];
    let p3 = quadBezierCurves[curveIndex][3];

    var windingNumber = 0.0;
    let windingSamples = 16u; // Number of segments to approximate the curve
  
    // Integrate along the curve to find the winding number
    for (var j: u32 = 0; j < windingSamples; j = j + 1u) {
        let t1 = f32(j) / f32(windingSamples);
        let t2 = f32(j + 1u) / f32(windingSamples);
        
        let point1 = evalBezier(p0, p1, p2, p3, t1);
        let point2 = evalBezier(p0, p1, p2, p3, t2);
        
        let v1 = point1 - pixelPos;
        let v2 = point2 - pixelPos;
        
        // Check if the segment crosses the positive x-axis from the pixel's perspective
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
    return windingNumber;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let curvesCount = arrayLength(&quadBezierCurves);

  if (curvesCount == 0u) {
    // Return a color indicating outside (0.0)
    return vec4f(0.0, 0.0, 0.0, 1.0);
  }

  // 1. Calculate the total winding number to determine if the pixel is inside or outside the shape.
  var totalWindingNumber = 0.0;
  for (var i: u32 = 0u; i < curvesCount; i = i + 1u) {
    totalWindingNumber += windingContribution(in.originalPosition, i);
  }
  // A non-zero winding number means the point is inside.
  // We use a negative sign for inside, positive for outside.
  let sign = select(1.0, -1.0, abs(totalWindingNumber) > 0.5);

  // 2. Find the closest pseudo-distance for each of the three color channels.
  var minRedDist = 1e38;
  var minGreenDist = 1e38;
  var minBlueDist = 1e38;

  for (var i: u32 = 0u; i < curvesCount; i = i + 1u) {
    let dist = pseudoDistance(in.originalPosition, i);
    let channel = i % 3u;

    if (channel == 0u) { // Red channel
      minRedDist = min(minRedDist, dist);
    } else if (channel == 1u) { // Green channel
      minGreenDist = min(minGreenDist, dist);
    } else { // Blue channel
      minBlueDist = min(minBlueDist, dist);
    }
  }

  // 3. The multi-channel signed distance is the median of the three channel distances.
  // The sign is applied *after* finding the median of the unsigned distances.
  let unsignedMedian = median(minRedDist, minGreenDist, minBlueDist);
  let finalSDF = sign * unsignedMedian;

  // 4. Normalize the distance to a 0-1 range for visualization.
  // A value of 0.5 represents the boundary of the shape.
  let range = 20.0; // This value depends on the scale of the shape.
  let color = vec3f(finalSDF / range + 0.5);

  // For debugging, you can visualize the individual signed channels:
  // let signedRed = sign * minRedDist;
  // let signedGreen = sign * minGreenDist;
  // let signedBlue = sign * minBlueDist;
  // let color = vec3f(signedRed / range + 0.5, signedGreen / range + 0.5, signedBlue / range + 0.5);

  return vec4f(color, 1.0);
}