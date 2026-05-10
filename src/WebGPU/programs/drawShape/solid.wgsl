
struct Uniforms {
  dist_start: f32,
  dist_end: f32,
  padding: vec2f, // Padding for alignment
  color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn getColor(_distance_X821b6_private: f32, t: f32, angle: f32, uv: vec2f, norm_uv: vec2f, norm_distance: f32) -> vec4f {
  return u.color;
}