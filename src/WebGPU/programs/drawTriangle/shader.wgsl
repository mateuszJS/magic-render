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
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex fn vs(
  vert: Vertex,
  @builtin(vertex_index) vertexIndex : u32
) -> VertexOutput {
  let normVertexIndex = vertexIndex % 3;

  var out: VertexOutput;
  if (normVertexIndex == 0) {
    out.position = u.worldViewProjection * vert.position_0;
    out.proximity = vec4f(1, 0, 0, 0);
  } else if (normVertexIndex == 1) {
    out.position = u.worldViewProjection * vert.position_1;
    out.proximity = vec4f(0, 1, 0, 0);
  } else {
    out.proximity = vec4f(0, 0, 1, 0);
    out.position = u.worldViewProjection * vert.position_2;
  }

  out.position_0 = vert.position_0;
  out.position_1 = vert.position_1;
  out.position_2 = vert.position_2;
  out.color = vert.color;
  out.corner_angles = vert.corner_angles;

  // let i = f32(normVertexIndex);
  // out.proximity = vec4f(i, (i + 1.0) % 3.0, (i + 2.0) % 3.0, 0);
  
  return out;
}

const PI = 3.14159265358979323846;

fn angleDifference(angle1: f32, angle2: f32) -> f32 {
  let delta = angle2 - angle1;
  return atan2(sin(delta), cos(delta)) + PI;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let max_value = max(in.proximity.x, max(in.proximity.y, in.proximity.z));
  let mask = in.proximity.xyz == vec3f(max_value);
  let imask = vec3i(select(vec3i(0), vec3i(1), mask));
  let index = u32(dot(imask, vec3i(0, 1, 2)));

  var closest_corner: vec4f;
  var half_closest_corner_angle: f32;
  if (index == 0) {
    closest_corner = vec4(in.position_0.xyz, in.corner_angles.x);
    let p0_to_p1_diff = in.position_1 - in.position_0;
    let p0_to_p1_angle = atan2(p0_to_p1_diff.y, p0_to_p1_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.x, p0_to_p1_angle);
  } else if (index == 1) {
    closest_corner = vec4(in.position_1.xyz, in.corner_angles.y);
    let p1_to_p2_diff = in.position_2 - in.position_1;
    let p1_to_p2_angle = atan2(p1_to_p2_diff.y, p1_to_p2_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.y, p1_to_p2_angle);
  } else {
    closest_corner = vec4(in.position_2.xyz, in.corner_angles.z);
    let p2_to_p0_diff = in.position_0 - in.position_2;
    let p2_to_p0_angle = atan2(p2_to_p0_diff.y, p2_to_p0_diff.x);
    half_closest_corner_angle = angleDifference(in.corner_angles.z, p2_to_p0_angle);
  }
  var correct_position = in.position;
  let canvas_height = 2.0 / u.worldViewProjection[1][1];
  correct_position.y = canvas_height - correct_position.y;
  // closest_corner.y = canvas_height - closest_corner.y;

  let dist = distance(closest_corner, correct_position);


    // pub fn angle_to(self: Point, other: anytype) f32 {
    //     const dx = other.x - self.x;
    //     const dy = other.y - self.y;
    //     return std.math.atan2(dy, dx);
    // }
  let radius = 20.0;
  let diff = correct_position - closest_corner;
  let corner_to_pixel_angle = atan2(diff.y, diff.x);

  // let angle_diff = angleDifference(corner_to_pixel_angle, closest_corner.a);
  // let angle_diff_adjusted = fract((angle_diff + PI) / (2.0 * PI)) * (2.0 * PI) - PI;

  // CORRECT!!!
  // return vec4f(1) * (PI + corner_to_pixel_angle) / (2 * PI);


  // let angle_diff_2 = angleDifference(corner_to_pixel_angle, angle_diff);
  // let angle_diff_2_adjusted = fract((angle_diff_2 + PI) / (2.0 * PI)) * (2.0 * PI) - PI;
  let angle_offset = corner_to_pixel_angle - closest_corner.a;
  let un_rotated_pixel_x = closest_corner.x + cos(angle_offset) * dist;

  // CORRECT!!!!
  // return vec4f((corner_to_pixel_angle + PI) / (2*PI), 0, 0, 1.0);

  // CORRECT!!!
  // return vec4f((closest_corner.a + PI) / (2*PI), 0, 0, 1.0);
  // return vec4f((angle_offset + PI) / (2*PI), 0, 0, 1.0);

  // CORRECT!!!
  // return vec4f(step(20.0, distance(closest_corner.x, un_rotated_pixel_x)), 0, 0, 1.0);

  // let un_rotated_pixel_y = closest_corner.y + sin(corner_to_pixel_angle - closest_corner.a) * dist;
  // return vec4f(1) * abs(correct_position.y - un_rotated_pixel_y) / 50.0;
  // return vec4f(1) * abs(correct_position.y - un_rotated_pixel_y) / 50.0;


  let threshold = radius / abs(tan(half_closest_corner_angle));

  if (un_rotated_pixel_x < closest_corner.x + threshold) {
    let circle_offset = radius / sin(half_closest_corner_angle);
    let circle_pos = vec2f(
      closest_corner.x + cos(closest_corner.a) * circle_offset,
      closest_corner.y + sin(closest_corner.a) * circle_offset
    );
    let circle_distance = distance(circle_pos, correct_position.xy);
    return mix(vec4f(1, 0, 0, 1), vec4f(0, 1, 0, 1), step(radius, circle_distance));
  } else {
    return vec4f(0, 0, 1, 1);
  }


  // let corner_radius = 20.0;
  // let edge = smoothstep(corner_radius - 1.0, corner_radius + 1.0, dist);

  //   // Alpha is 0 outside the corner, 1 inside, smooth at the edge
  // let alpha = 1.0 - edge;
  // return vec4f(1, 1, 1, 1) * alpha;


  // let v = smoothstep(35.0, 40.0, dist);
  // return vec4f(v, v, v, 1);

  // if (index == 0) {
  //   return vec4f(1, 0, 0, 1);
  // } else if (index == 1) {
  //   return vec4f(0, 1, 0, 1);
  // } else if(index == 2) {
  //   return vec4f(0, 0, 1, 1);
  // } else {
  //   return vec4f(0);
  // }

  // return vec4f(in.proximity.xyz, 1.0);

  
  // let dist = distance(in.position.xy, in.corner);
  // let edge = smoothstep(in.corner_radius - 1.0, in.corner_radius + 1.0, dist);
  // let value: f32 = 1.0 - step(in.corner_offset.x, distance_from_center);
  // return in.color;
}
