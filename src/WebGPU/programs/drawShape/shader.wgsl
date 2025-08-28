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
  let sdf = textureLoad(texture, vec2u(vsOut.uv));

  // let stroke_factor = select(0.5, 0.0, sdf.g > 1.0);
  let stroke_factor = 0.0;
  let is_filled = select(0.0, 1.0, sdf.r > -u.stroke_width * stroke_factor);
  var color = select(u.stroke_color, u.fill_color, sdf.r > u.stroke_width * stroke_factor);

  color = vec4f(sdf.r / 100.0, sdf.g % 1, sdf.b / (2 * 3.1415926), 1.0);
  // color = select(vec4f(0.5, 0, 0, 1), vec4f(0, 0, 0.5, 1), u32(sdf.r / 20.0) % 2 == 0);

  return color * is_filled;
}
