struct Vertex {
  @location(0) position_0: vec4f,
  @location(1) position_1: vec4f,
  @location(2) position_2: vec4f,
  @location(3) color: vec4f,
  @location(4) corner_angles: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) @interpolate(flat) position_0: vec4f,
  @location(1) @interpolate(flat) position_1: vec4f,
  @location(2) @interpolate(flat) position_2: vec4f,
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
    out.position = vert.position_0;
    out.proximity = vec4f(1, 0, 0, 0);
  } else if (normVertexIndex == 1) {
    out.position = vert.position_1;
    out.proximity = vec4f(0, 1, 0, 0);
  } else {
    out.proximity = vec4f(0, 0, 1, 0);
    out.position = vert.position_2;
  }

  out.cartesian_pixel_coords = vec2f(out.position.x, out.position.y);

  out.position = u.worldViewProjection * out.position;

  out.position_0 = vert.position_0;
  out.position_1 = vert.position_1;
  out.position_2 = vert.position_2;
  out.color = vert.color;
  out.corner_angles = vert.corner_angles;

  return out;
}

const PI = 3.14159265358979323846;

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

  var closest_corner: vec2f;
  var closest_corner_angle: f32;
  var half_closest_corner_angle: f32;
  if (index == 0) {
    closest_corner = in.position_0.xy;
    closest_corner_angle = in.corner_angles.x;
    let p0_to_p1_diff = in.position_1 - in.position_0;
    let p0_to_p1_angle = atan2(p0_to_p1_diff.y, p0_to_p1_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.x, p0_to_p1_angle);
  } else if (index == 1) {
    closest_corner = in.position_1.xy;
    closest_corner_angle = in.corner_angles.y;
    let p1_to_p2_diff = in.position_2 - in.position_1;
    let p1_to_p2_angle = atan2(p1_to_p2_diff.y, p1_to_p2_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.y, p1_to_p2_angle);
  } else {
    closest_corner = in.position_2.xy;
    closest_corner_angle = in.corner_angles.z;
    let p2_to_p0_diff = in.position_0 - in.position_2;
    let p2_to_p0_angle = atan2(p2_to_p0_diff.y, p2_to_p0_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.z, p2_to_p0_angle);
  }

  let dist = distance(closest_corner, pixel);

  let radius = 20.0;

  let diff = pixel - closest_corner;
  let corner_to_pixel_angle = atan2(diff.y, diff.x);
  let un_rotate_angle = corner_to_pixel_angle - closest_corner_angle;
  let un_rotated_pixel_x = closest_corner.x + cos(un_rotate_angle) * dist;


  let threshold = radius / abs(tan(half_closest_corner_angle));

  if (un_rotated_pixel_x < closest_corner.x + threshold) {
  // if (un_rotated_pixel_x < closest_corner.x + threshold - 1.3) { // sometimes on the edge we got wrogn results
    let circle_offset = radius / sin(half_closest_corner_angle);
    let circle_pos = vec2f(
      closest_corner.x + cos(closest_corner_angle) * circle_offset,
      closest_corner.y + sin(closest_corner_angle) * circle_offset
    );
    let circle_distance = distance(circle_pos, pixel.xy);
    return mix(vec4f(1, 0, 0, 1), vec4f(0, 1, 0, 1), step(radius, circle_distance));
  } else {
    return vec4f(0, 0, 1, 1);
  }
}
