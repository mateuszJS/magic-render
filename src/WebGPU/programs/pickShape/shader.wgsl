const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;


struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

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


fn g_to_bezier_pos(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let local_t = fract(global_t);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );

  let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;
  if (is_straight_line) {
    return mix(curve.p0, curve.p3, local_t);
  }

  return bezier_point(curve, local_t);
}

struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: vec4u,
};

struct Uniforms {
  dist_start: f32,
  dist_end: f32,
};

@group(0) @binding(0) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(1) var<uniform> u: Uniforms;
@group(0) @binding(2) var texture: texture_2d<f32>;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) id: vec4u
};

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;

  out.position = camera_projection * vec4f(vert.position.xy, 0.0, 1.0);
  out.id = vert.id;

  let size = textureDimensions(texture);
  out.uv = vert.position.zw * vec2f(size);

  return out;
}

@fragment fn fs(vsOut: VertexOutput) -> @location(0) vec4u {
  let t = textureLoad(texture, vec2u(vsOut.uv), 0).r;
  let sanitized_t = abs(t) - 1;
  let curve_pos = g_to_bezier_pos(sanitized_t);
  let distance = length(curve_pos - vsOut.uv);
  let signed_distance = distance * sign(t);

  if (signed_distance > u.dist_start || signed_distance < u.dist_end) {
    discard;
  }

  return vsOut.id;
}
