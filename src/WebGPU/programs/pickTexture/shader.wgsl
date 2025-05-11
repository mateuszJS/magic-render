struct Vertex {
  @location(0) position: vec4f,
  @location(1) uv: vec2f,
  @location(2) id: f32,
};

struct Uniforms {
  worldViewProjection: mat4x4f
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) texCoord: vec2f,
  @location(1) @interpolate(flat) id: f32
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_2d<f32>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  // maybe we should pass offsets from the position instead of... position?
  out.position = u.worldViewProjection * vert.position;
  out.texCoord = vert.uv;
  out.id = vert.id;

  return out;
}


// @fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
@fragment fn fs(in: VertexOutput) -> @location(0) u32 {
  let alpha = textureSample(ourTexture, ourSampler, in.texCoord).a;

  if (alpha < 0.1) {
    discard; // r32uint doesn't support blending so only skipping pixels lefts
  }

  return u32(in.id);
}
