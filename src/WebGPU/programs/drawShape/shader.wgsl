const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;

struct Uniforms {
  stroke_width: f32,
  fill_color: vec4f,
  stroke_color: vec4f,
};

struct Vertex {
  @location(0) position: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var texture: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  let size = textureDimensions(texture);
  return VSOutput(
    camera_projection * vec4f(vert.position.xy, 0.0, 1.0),
    vert.position.zw * vec2f(size),
  );
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = textureLoad(texture, vec2u(vsOut.uv)).r;
  let x = u.fill_color.r;

  let is_filled = select(0.0, 1.0, sdf > -u.stroke_width * 0.5);
  let color = select(u.stroke_color, u.fill_color, sdf > u.stroke_width * 0.5);

  return color * is_filled;
  // return vec4f(value, u.fill_color.r, 0.0, 1.0);
}
