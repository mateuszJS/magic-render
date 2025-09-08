const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;

struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: u32,
};

struct Uniforms {
  dist_start: f32,
  dist_end: f32,
};

@group(0) @binding(0) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(1) var<uniform> u: Uniforms;
@group(0) @binding(2) var texture: texture_storage_2d<rgba32float, read>;

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) id: u32
};

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;

  out.position = camera_projection * vec4f(vert.position.xy, 0.0, 1.0);
  out.id = vert.id;

  let size = textureDimensions(texture);
  out.uv = vert.position.zw * vec2f(size);

  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) u32 {
  let dist = textureLoad(texture, vec2u(in.uv)).r;

  if (dist > u.dist_start || dist < u.dist_end) {
    discard;
  }

  return in.id;
}
