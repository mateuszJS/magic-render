struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: vec4u,
};

struct Uniforms {
  worldViewProjection: mat4x4f
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) texCoord: vec2f,
  @location(1) @interpolate(flat) id: vec4u
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_2d<f32>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;

  out.position = u.worldViewProjection * vec4f(vert.position.xy, 0.0, 1.0);
  out.texCoord = vert.position.zw;
  out.id = vert.id;

  return out;
}


@fragment fn fs(in: VertexOutput) -> @location(0) vec4u {
  let alpha = textureSample(ourTexture, ourSampler, in.texCoord).a;

  if (alpha < 0.1) {
    discard; // r32uint doesn't support blending so only skipping pixels lefts
  }

  return in.id;
}
