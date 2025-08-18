const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;

struct Uniforms {
  stroke_width: f32,
  fill_color: vec4f,
  stroke_color: vec4f,
};

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

struct Vertex {
  @location(0) position: vec2f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var sdf: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) world_pos: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {

  return VSOutput(
    camera_projection * vec4f(vert.position, 0.0, 1.0),
    vert.position
  );
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  // let value = textureSample(sdf, ourSampler, vsOut.world_pos).r;
  let value = textureLoad(sdf, vec2u(vsOut.world_pos)).r;
  return vec4f(value, u.fill_color.r, 0.0, 1.0);
}
