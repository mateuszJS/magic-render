const PI = 3.14159265358979323846;

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
  @location(3) color: vec4f,
  @location(4) proximity: vec4f,
  @location(5) pixel: vec2f,
  @location(6) radius: f32,
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
    out.proximity = vec4f(1, 0, 0, 0);
    out.radius = 10.0;//vert.radius_list.x;
  } else if (normVertexIndex == 1) {
    out.position = vec4f(vert.p1.xy, 0, 1);
    out.proximity = vec4f(0, 1, 0, 0);
    out.radius = 20.0;//vert.radius_list.y;
  } else {
    out.position = vec4f(vert.p2.xy, 0, 1);
    out.proximity = vec4f(0, 0, 1, 0);
    out.radius = 20.0;//vert.radius_list.z;
  }

  out.pixel = vec2f(out.position.x, out.position.y);

  out.position = u.worldViewProjection * out.position;

  out.p0 = vert.p0;
  out.p1 = vert.p1;
  out.p2 = vert.p2;
  out.color = vert.color;

  return out;
}


fn angleDifference(angle1: f32, angle2: f32) -> f32 {
  let delta = angle2 - angle1;
  return atan2(sin(delta), cos(delta)) + PI;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let max_value = max(in.proximity.x, max(in.proximity.y, in.proximity.z));
  let mask = in.proximity.xyz == vec3f(max_value);
  let imask = vec3i(select(vec3i(0), vec3i(1), mask));
  let index = u32(dot(imask, vec3i(0, 1, 2)));

  var p: vec2f; // closest corner
  var p_circle: vec2f; // closest corner's circle position

  if (index == 0) {
    p = in.p0.xy;
    p_circle = in.p0.zw;
  } else if (index == 1) {
    p = in.p1.xy;
    p_circle = in.p1.zw;
  } else {
    p = in.p2.xy;
    p_circle = in.p2.zw;
  }

  let p_circle_distance = distance(p_circle, p);
  let threshold = sqrt(pow(p_circle_distance, 2) - pow(in.radius, 2)); // behind this value is roudned corner
  let dist = distance(p, in.pixel);

  if (dist < threshold) {
    let circle_distance = distance(p_circle, in.pixel);
    return mix(vec4f(1, 0, 0, 1), vec4f(0, 1, 0, 1), step(in.radius, circle_distance));
  } else {
    return vec4f(0, 0, 1, 1);
  }
}
