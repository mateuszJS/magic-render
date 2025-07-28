struct Vertex {
  @location(0) position: vec4f,
};

struct Uniforms {
  cameraProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) texCoord: vec2f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_2d<f32>;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  // maybe we should pass offsets from the position instead of... position?
  out.position = u.cameraProjection * vec4f(vert.position.xy, 0, 1);
  out.texCoord = vert.position.zw;
  
  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  return textureSample(ourTexture, ourSampler, in.texCoord);
}
