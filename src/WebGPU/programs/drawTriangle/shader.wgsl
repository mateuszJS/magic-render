const PI = 3.14159265358979323846;
const EPSILON = 1.1920929e-7;

struct Vertex {
  @location(0) p0: vec4f,
  @location(1) p1: vec4f,
  @location(2) p2: vec4f,
  @location(3) color: vec4f,
  @location(4) radius_list: vec3f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) @interpolate(flat) p0: vec4f,
  @location(1) @interpolate(flat) p1: vec4f,
  @location(2) @interpolate(flat) p2: vec4f,
  @location(3) @interpolate(flat) color: vec4f,
  @location(4) pixel: vec2f,
  @location(5) @interpolate(flat) radius_list: vec3f,
  @location(6) @interpolate(flat) threshold_list: vec3f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex fn vs(
  vert: Vertex,
  @builtin(vertex_index) vertexIndex : u32
) -> VertexOutput {
  let normVertexIndex = vertexIndex % 3;

  var out: VertexOutput;
  if (normVertexIndex == 0) {
    out.position = vec4f(vert.p0.xy, 0, 1);
  } else if (normVertexIndex == 1) {
    out.position = vec4f(vert.p1.xy, 0, 1);
  } else {
    out.position = vec4f(vert.p2.xy, 0, 1);
  }

  out.pixel = vec2f(out.position.x, out.position.y);

  out.position = u.worldViewProjection * out.position;

  out.p0 = vert.p0;
  out.p1 = vert.p1;
  out.p2 = vert.p2;
  out.color = vert.color;
  out.radius_list = vert.radius_list;

  let p0_circle_dist = distance(vert.p0.xy, vert.p0.zw);
  let p1_circle_dist = distance(vert.p1.xy, vert.p1.zw);
  let p2_circle_dist = distance(vert.p2.xy, vert.p2.zw);

  out.threshold_list = vec3f(
    sqrt(pow(p0_circle_dist, 2) - pow(vert.radius_list.x, 2)),
    sqrt(pow(p1_circle_dist, 2) - pow(vert.radius_list.y, 2)),
    sqrt(pow(p2_circle_dist, 2) - pow(vert.radius_list.z, 2)),
  ); // behind this value is roudned corner

  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let p0_circle_dist = distance(in.p0.xy, in.pixel) - in.threshold_list.x;
  let p1_circle_dist = distance(in.p1.xy, in.pixel) - in.threshold_list.y;
  let p2_circle_dist = distance(in.p2.xy, in.pixel) - in.threshold_list.z;
  
  let min_circle_dist = min(
    p0_circle_dist,
    min(p1_circle_dist, p2_circle_dist)
  );

  var p: vec2f; // closest corner
  var p_circle: vec2f; // closest corner's circle position
  var radius: f32;
  var threshold: f32;

  if (abs(min_circle_dist - p0_circle_dist) <= EPSILON) {
    p = in.p0.xy;
    p_circle = in.p0.zw;
    radius = in.radius_list.x;
    threshold = in.threshold_list.x;
  } else if (abs(min_circle_dist - p1_circle_dist) <= EPSILON) {
    p = in.p1.xy;
    p_circle = in.p1.zw;
    radius = in.radius_list.y;
    threshold = in.threshold_list.y;
  } else {
    p = in.p2.xy;
    p_circle = in.p2.zw;
    radius = in.radius_list.z;
    threshold = in.threshold_list.z;
  }

  let dist = distance(p, in.pixel);

  if (dist < threshold) {
    let circle_distance = distance(p_circle, in.pixel);
    return in.color * (1.0 - step(radius, circle_distance));
  } else {
    return in.color;
  }
}
