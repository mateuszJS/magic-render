
struct Uniforms {
  stroke_width: f32,
  fill_color: vec4f,
  stroke_color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn getStrokeColor(sdf: vec4f, uv: vec2f, norm_uv: vec2f) -> vec4f {
  return u.stroke_color;
  // return select(vec4f(0, 0, 0, 0), u.stroke_color, u.stroke_width < EPSILON);
}

fn getFillColor(sdf: vec4f, uv: vec2f, norm_uv: vec2f) -> vec4f {
  return u.fill_color;
}