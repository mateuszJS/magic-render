const PI = 3.14159265358979323846;
const EPSILON = 1.1920929e-7;

struct Vertex {
  @location(0) p0: vec4f, //xy -> corner position, zw -> circle position
  @location(1) p1: vec4f,
  @location(2) p2: vec4f,
  @location(3) id: u32,
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
  @location(3) @interpolate(flat) id: u32,
  @location(4) pixel: vec2f,
  @location(5) @interpolate(flat) radius_list: vec3f,
  @location(6) @interpolate(flat) threshold_list: vec3f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn threshold_pythagorean_leg(corner: vec4f, radius: f32) -> f32 {
  let p_circle_dist = distance(corner.xy, corner.zw);
  // Pythagorean theorem, finding one leg of a right triangle when you know the hypotenuse and the other leg.
  return sqrt(p_circle_dist * p_circle_dist - radius * radius);
}

@vertex fn vs(
  vert: Vertex,
  @builtin(vertex_index) vertex_index : u32
) -> VertexOutput {
  var out: VertexOutput;

  let positions = array<vec2f, 3>(vert.p0.xy, vert.p1.xy, vert.p2.xy);
  out.position = vec4f(positions[vertex_index], 0, 1);

  out.pixel = vec2f(out.position.x, out.position.y);

  out.position = u.worldViewProjection * out.position;

  out.p0 = vert.p0;
  out.p1 = vert.p1;
  out.p2 = vert.p2;
  out.id = vert.id;

  out.radius_list = vert.radius_list;

  out.threshold_list = vec3f(
    threshold_pythagorean_leg(vert.p0, vert.radius_list.x),
    threshold_pythagorean_leg(vert.p1, vert.radius_list.y),
    threshold_pythagorean_leg(vert.p2, vert.radius_list.z),
  ); // behind this value is a ounded corner

  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) u32 {
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


  let circle_distance = distance(p_circle, in.pixel);
  let edge_width = fwidth(circle_distance);

  let circle_alpha = 1.0 - smoothstep(radius - edge_width, radius + edge_width, circle_distance);
  let dist = distance(p, in.pixel);
  let alpha = mix(circle_alpha, 1.0,  step(threshold, dist)); // if threshold <= dist, use circle alpha, otherwise use 1.0

  if (alpha < 0.1) {
    discard; // r32uint doesn't support blending so only skipping pixels lefts
  }

  return in.id;
}
