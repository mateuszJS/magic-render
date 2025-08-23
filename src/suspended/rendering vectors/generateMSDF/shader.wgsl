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

const MSDFGEN_CUBIC_SEARCH_STARTS = 4;
const MSDFGEN_CUBIC_SEARCH_STEPS = 4;
const DEFAULT_ANGLE_THRESHOLD = 3.0;

fn median(a: f32, b: f32, c: f32) -> f32 {
  if ((a < b && b < c) || (c < b && b < a)) {
    return b;
  } else if ((b < a && a < c) || (c < a && a < b)) {
    return a;
  } else {
    return c;
  }
}

struct SignedDistance {
  distance: f32,
  dot: f32,
};

fn isSmallerThan(a: SignedDistance, b: SignedDistance) -> bool {
  return abs(a.distance) < abs(b.distance) || (floatIsEqual(abs(a.distance), abs(b.distance)) && a.dot < b.dot);
}

fn isSmallerOrEqualTo(a: SignedDistance, b: SignedDistance) -> bool {
  return abs(a.distance) < abs(b.distance) || (floatIsEqual(abs(a.distance), abs(b.distance)) && a.dot <= b.dot);
}

const WHITE = 7u; // 111
const MAGENTA = 5u; // 101
const YELLOW = 6u; // 110
const CYAN = 3u; // 011
const RED = 1u; // 001
const GREEN = 2u; // 010
const BLUE = 4u; // 100

const NO_EDGE_INDEX = 0xffffffffu; // represents NULL
  const EPSILON = 1e-6;


fn floatIsEqual(a: f32, b: f32) -> bool {
  return abs(a - b) <= EPSILON;
}

// https://github.com/Chlumsky/msdfgen/blob/master/core/edge-segments.cpp#L132
fn direction(curveIndex: u32, param: f32) -> vec2f {
    let p0 = quadBezierCurves[curveIndex][0];
    let p1 = quadBezierCurves[curveIndex][1];
    let p2 = quadBezierCurves[curveIndex][2];
    let p3 = quadBezierCurves[curveIndex][3];

    let tangent = mix(mix(p1-p0, p2-p1, param), mix(p2-p1, p3-p2, param), param);
    if (floatIsEqual(tangent.x, 0) && floatIsEqual(tangent.y, 0)) {
        if (floatIsEqual(param, 0)) {
          return p2-p0;
        }
        if (floatIsEqual(param, 1)) {
          return p3-p1;
        }
    }
    return tangent;
}

fn normalize_custom(v: vec2f, allow_zero: bool) -> vec2f {
    let len: f32 = length(v); // Calculate the length

    // Check if the length is effectively non-zero
    if (len >= EPSILON) {
        return v / len; // Normalize if length is sufficient
    }

    // Fallback behavior for zero-length vectors
    if (allow_zero) {
        return vec2f(0.0, 0.0); // If allowed, return a zero vector
    } else {
        // If not allowed, return (0, 1) as a default non-zero unit vector
        // This implicitly assumes the 'up' direction is (0,1) for 2D.
        return vec2f(0.0, 1.0);
    }
}

// Vector2 https://github.com/Chlumsky/msdfgen/blob/master/core/Vector2.hpp
fn crossProduct(a: vec2f, b: vec2f) -> f32 {
    return a.x*b.y-a.y*b.x;
}

// https://github.com/Chlumsky/msdfgen/blob/master/core/arithmetics.hpp#L59
fn nonZeroSign(n: f32) -> f32 {
  return select(-1.0, 1.0, n > 0.0);
}

struct SignedDistanceAndParam {
  signedDistance: SignedDistance,
  param: f32,
}

// https://github.com/Chlumsky/msdfgen/blob/master/core/edge-segments.cpp#L228
fn signedDistance(curveIndex: u32, origin: vec2f) -> SignedDistanceAndParam {
    var result: SignedDistanceAndParam;

    let p0 = quadBezierCurves[curveIndex][0];
    let p1 = quadBezierCurves[curveIndex][1];
    let p2 = quadBezierCurves[curveIndex][2];
    let p3 = quadBezierCurves[curveIndex][3];
    let curve_length = quadBezierCurves[curveIndex][4].x;

    let qa = p0-origin;
    let ab = p1-p0;
    let br = p2-p1-ab;
    let custom_as = (p3-p2)-(p2-p1)-br;

    var epDir = direction(curveIndex, 0.0);
    var minDistance = nonZeroSign(crossProduct(epDir, qa)) * length(qa); // distance from A
    result.param = -dot(qa, epDir) / dot(epDir, epDir);

    {
        var distance = length(p3-origin); // distance from B
        if (distance < abs(minDistance)) {
            epDir = direction(curveIndex, 1.0);
            minDistance = nonZeroSign(crossProduct(epDir, p3-origin))*distance;
            result.param = dot(epDir-(p3-origin), epDir)/dot(epDir, epDir);
        }
    }

    // Iterative minimum distance search
    // let samples = u32(curve_length);
    for (var i: u32 = 0u; i <= MSDFGEN_CUBIC_SEARCH_STARTS; i++) {
        var t = 1.0 / f32(MSDFGEN_CUBIC_SEARCH_STARTS) * f32(i);
        var qe = qa+3*t*ab+3*t*t*br+t*t*t*custom_as;
        var d1 = 3*ab+6*t*br+3*t*t*custom_as;
        var d2 = 6*br+6*t*custom_as;
        var improvedT = t-dot(qe, d1)/(dot(d1, d1)+dot(qe, d2));
        if (improvedT > 0.0 && improvedT < 1.0) {
            var remainingSteps = MSDFGEN_CUBIC_SEARCH_STEPS;

            loop {
                t = improvedT;
                qe = qa+3*t*ab+3*t*t*br+t*t*t*custom_as;
                d1 = 3*ab+6*t*br+3*t*t*custom_as;
                remainingSteps--;
                if (remainingSteps == 0) {
                    break;
                }
                d2 = 6*br+6*t*custom_as;
                improvedT = t-dot(qe, d1)/(dot(d1, d1)+dot(qe, d2));

                if (improvedT <= 0.0 || improvedT >= 1.0) {
                    break;
                }
            }

            let  distance = length(qe);
            if (distance < abs(minDistance)) {
                minDistance = nonZeroSign(crossProduct(d1, qe))*distance;
                result.param = t;
            }
        }
    }

  result.signedDistance.distance = minDistance;

  if (result.param >= 0.0 && result.param <= 1.0) {
    result.signedDistance.dot = 0.0;
  } else if (result.param < 0.5) {
    result.signedDistance.dot = abs(dot(normalize_custom(direction(curveIndex, 0.0), false), normalize_custom(qa, false)));
  } else {
    result.signedDistance.dot = abs(dot(normalize_custom(direction(curveIndex, 1.0), false), normalize_custom(p3-origin, false)));
  }

  return result;
}

fn cubic_point(curveIndex: u32, param: f32) -> vec2f {
    let p0 = quadBezierCurves[curveIndex][0];
    let p1 = quadBezierCurves[curveIndex][1];
    let p2 = quadBezierCurves[curveIndex][2];
    let p3 = quadBezierCurves[curveIndex][3];

    let p12 = mix(p1, p2, param);
    return mix(mix(mix(p0, p1, param), p12, param), mix(p12, mix(p2, p3, param), param), param);
}

fn distanceToPerpendicularDistance(curveIndex: u32, distance: SignedDistance, origin: vec2f, param: f32) -> f32 {
    if (param < 0.0) {
        let dir = normalize_custom(direction(curveIndex, 0.0), false);
        let aq = origin - cubic_point(curveIndex, 0.0);
        let ts = dot(aq, dir);
        if (ts < 0.0) {
            let perpendicularDistance = crossProduct(aq, dir);
            if (abs(perpendicularDistance) < abs(distance.distance) || floatIsEqual(abs(perpendicularDistance), abs(distance.distance))) {
                return perpendicularDistance;
            }
        }
    } else if (param > 1.0) {
        let dir = normalize_custom(direction(curveIndex, 1.0), false);
        let bq = origin-cubic_point(curveIndex, 1.0);
        let ts = dot(bq, dir);
        if (ts > 0.0) {
            let perpendicularDistance = crossProduct(bq, dir);
            if (abs(perpendicularDistance) < abs(distance.distance) || floatIsEqual(abs(perpendicularDistance), abs(distance.distance))) {
                return perpendicularDistance;
            }
        }
    }

    return distance.distance;
}


struct EdgeSegment {
  index: u32,
  color: u32,
}

struct ChannelInfo {
  minDistance: SignedDistance,
  nearEdgeSegment: EdgeSegment, // should be wrapped in "EdgeHolder"
  nearParam: f32,
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  // https://github.com/Chlumsky/msdfgen/blob/master/core/msdfgen.cpp#L234
  var _rEdgeSegment: EdgeSegment; _rEdgeSegment.index = NO_EDGE_INDEX; _rEdgeSegment.color = WHITE;
  var _gEdgeSegment: EdgeSegment; _gEdgeSegment.index = NO_EDGE_INDEX; _gEdgeSegment.color = WHITE;
  var _bEdgeSegment: EdgeSegment; _bEdgeSegment.index = NO_EDGE_INDEX; _bEdgeSegment.color = WHITE;

  var r: ChannelInfo; r.minDistance.distance = 10000000000.0; // idk why in c++ code it looks like it sohuld be -DOUBLE_MAX
  var g: ChannelInfo; g.minDistance.distance = 10000000000.0;
  var b: ChannelInfo; b.minDistance.distance = 10000000000.0;


  let curvesCount = arrayLength(&quadBezierCurves);
  var color: u32 = MAGENTA;
  for (var i: u32 = 0u; i < curvesCount; i++) {
    let distanceAndParam = signedDistance(i, in.originalPosition);
    let distance = distanceAndParam.signedDistance;
    let param = distanceAndParam.param;

    if ((color & RED) > 0 && isSmallerThan(distance, r.minDistance)) {
      r.minDistance = distance;
      r.nearEdgeSegment.index = i;
      r.nearEdgeSegment.color = color;
      r.nearParam = param;
    }

    if ((color & GREEN) > 0 && isSmallerThan(distance, g.minDistance)) {
      g.minDistance = distance;
      g.nearEdgeSegment.index = i;
      g.nearEdgeSegment.color = color;
      g.nearParam = param;
    }

    if ((color & BLUE) > 0 && isSmallerThan(distance, b.minDistance)) {
      b.minDistance = distance;
      b.nearEdgeSegment.index = i;
      b.nearEdgeSegment.color = color;
      b.nearParam = param;
    }

    if (color == YELLOW) {
      color = CYAN;
    } else {
      color = YELLOW;
    }
  }

  // https://github.com/Chlumsky/msdfgen/blob/master/core/msdfgen.cpp#L259
  // if (r.nearEdgeSegment.index != NO_EDGE_INDEX) {
  //   r.minDistance.distance = distanceToPerpendicularDistance(r.nearEdgeSegment.index, r.minDistance, in.originalPosition, r.nearParam);
  // }
  // if (g.nearEdgeSegment.index != NO_EDGE_INDEX) {
  //   g.minDistance.distance = distanceToPerpendicularDistance(g.nearEdgeSegment.index, g.minDistance, in.originalPosition, g.nearParam);
  // }
  // if (b.nearEdgeSegment.index != NO_EDGE_INDEX) {
  //   b.minDistance.distance = distanceToPerpendicularDistance(b.nearEdgeSegment.index, b.minDistance, in.originalPosition, b.nearParam);
  // }

  let v = median(r.minDistance.distance, g.minDistance.distance, b.minDistance.distance);
  // return vec4f(v, v, v, 1.0);
  return vec4f(r.minDistance.distance / 10.0, g.minDistance.distance / 10.0, b.minDistance.distance / 10.0, 1.0);
  // return vec4f(r.minDistance.distance / 10.0, g.minDistance.distance / 10.0, b.minDistance.distance / 10.0, 1.0);
}



    


    // calculating color for the next edge
