const PI = 3.14159265358979323846;

struct Vertex {
  @location(0) p0: vec4f,
  @location(1) p1: vec4f,
  @location(2) p2: vec4f,
  @location(3) color: vec4f,
  @location(4) corner_angles: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) @interpolate(flat) p0: vec2f,
  @location(1) @interpolate(flat) p1: vec2f,
  @location(2) @interpolate(flat) p2: vec2f,
  @location(3) color: vec4f,
  @location(4) proximity: vec4f,
  @location(5) corner_angles: vec4f,
  @location(6) cartesian_pixel_coords: vec2f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex fn vs(
  vert: Vertex,
  @builtin(vertex_index) vertexIndex : u32
) -> VertexOutput {
  let normVertexIndex = vertexIndex % 3;

  var out: VertexOutput;
  if (normVertexIndex == 0) {
    out.position = vert.p0;
    out.proximity = vec4f(1, 0, 0, 0);
  } else if (normVertexIndex == 1) {
    out.position = vert.p1;
    out.proximity = vec4f(0, 1, 0, 0);
  } else {
    out.position = vert.p2;
    out.proximity = vec4f(0, 0, 1, 0);
  }

  out.cartesian_pixel_coords = vec2f(out.position.x, out.position.y);

  out.position = u.worldViewProjection * out.position;

  out.p0 = vert.p0.xy;
  out.p1 = vert.p1.xy;
  out.p2 = vert.p2.xy;
  out.color = vert.color;
  out.corner_angles = vert.corner_angles;

  return out;
}


fn angleDifference(angle1: f32, angle2: f32) -> f32 {
  let delta = angle2 - angle1;
  return atan2(sin(delta), cos(delta)) + PI;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  var pixel = in.cartesian_pixel_coords;

  let max_value = max(in.proximity.x, max(in.proximity.y, in.proximity.z));
  let mask = in.proximity.xyz == vec3f(max_value);
  let imask = vec3i(select(vec3i(0), vec3i(1), mask));
  let index = u32(dot(imask, vec3i(0, 1, 2)));

  var p: vec2f; // closest corner
  var p_angle: f32; // middle angle from the corner
  var neighbor_p: vec2f;
  if (index == 0) {
    p = in.p0;
    p_angle = in.corner_angles.x;
    neighbor_p = in.p1;
  } else if (index == 1) {
    p = in.p1;
    p_angle = in.corner_angles.y;
    neighbor_p = in.p2;
  } else {
    p = in.p2;
    p_angle = in.corner_angles.z;
    neighbor_p = in.p0;
  }

  let neighbor_dist = neighbor_p - p;
  let neighbor_angle = atan2(neighbor_dist.y, neighbor_dist.x);
  let diff_mid_to_neighbour_angle = angleDifference(p_angle, neighbor_angle); // not sure if we need angleDifference function

  let dist = distance(p, pixel);

  let radius = 20.0;

  let diff = pixel - p;
  let corner_to_pixel_angle = atan2(diff.y, diff.x);
  let un_rotate_angle = corner_to_pixel_angle - p_angle;
  let un_rotated_pixel_x = p.x + cos(un_rotate_angle) * dist;


  let threshold = radius / abs(tan(diff_mid_to_neighbour_angle)); // behind this value is roudned corner

  if (un_rotated_pixel_x < p.x + threshold) {
  // if (un_rotated_pixel_x < closest_corner.x + threshold - 1.3) { // sometimes on the edge we got wrogn results
    let circle_offset = radius / sin(diff_mid_to_neighbour_angle);
    let circle_pos = vec2f(
      p.x + cos(p_angle) * circle_offset,
      p.y + sin(p_angle) * circle_offset
    );
    let circle_distance = distance(circle_pos, pixel.xy);
    return mix(vec4f(1, 0, 0, 1), vec4f(0, 1, 0, 1), step(radius, circle_distance));
  } else {
    return vec4f(0, 0, 1, 1);
  }
}
