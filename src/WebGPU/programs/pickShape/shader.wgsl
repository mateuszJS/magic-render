const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;

struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: u32,
};

struct Uniforms {
  stroke_width: f32,
  fill_color: vec4f,
  stroke_color: vec4f,
};

@group(0) @binding(0) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(1) var<uniform> u: Uniforms;
@group(0) @binding(2) var sdf: texture_storage_2d<rgba32float, read>;

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) id: u32
};

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;

  out.position = camera_projection * vec4f(vert.position.xy, 0.0, 1.0);
  out.id = vert.id;

  let size = textureDimensions(sdf);
  out.uv = vert.position.zw * vec2f(size);

  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) u32 {
  // let value = textureSample(sdf, ourSampler, in.world_pos).r;
  let value = textureLoad(sdf, vec2u(in.uv)).r / 10.0;
  let x = u.fill_color.r;
    if (value < 0.1) {
    discard; // r32uint doesn't support blending so only skipping pixels lefts
  }

  return in.id;
}
