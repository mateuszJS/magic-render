
struct Uniforms {
  dist_start: f32,
  dist_end: f32,
  padding: vec2f, // Padding for alignment
  color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn getColor(sdf: vec4f, uv: vec2f, norm_uv: vec2f) -> vec4f {
  return u.color;
}