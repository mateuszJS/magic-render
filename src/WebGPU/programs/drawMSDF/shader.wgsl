struct Vertex {
  @location(0) position: vec4f,
  @location(1) uv: vec2f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
  screenPxDistance: f32,
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
  out.position = u.worldViewProjection * vert.position;
  out.texCoord = vert.uv;
  
  return out;
}

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let msdf = textureSample(ourTexture, ourSampler, in.texCoord);
  let sd = median(msdf.r, msdf.g, msdf.b);

  let screenPxDistance = u.screenPxDistance * (sd - 0.5);
  let opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
  return vec4f(opacity, opacity, opacity, opacity);
}
