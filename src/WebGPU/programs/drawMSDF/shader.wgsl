struct Vertex {
  @location(0) p0_position: vec4f,
  @location(1) p0_uv: vec2f,
  @location(2) p1_position: vec4f,
  @location(3) p1_uv: vec2f,
  @location(4) p2_position: vec4f,
  @location(5) p2_uv: vec2f,
  @location(6) color: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) texCoord: vec2f,
  @location(1) @interpolate(flat) color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;
@group(0) @binding(1) var ourSampler: sampler;
@group(0) @binding(2) var ourTexture: texture_2d<f32>;

@vertex fn vs(vert: Vertex, @builtin(vertex_index) vertexIndex : u32) -> VertexOutput {
  let normVertexIndex = vertexIndex % 3;

  var out: VertexOutput;
  if (normVertexIndex == 0) {
      out.position = u.worldViewProjection * vert.p0_position;
      out.texCoord = vert.p0_uv;
  } else if (normVertexIndex == 1) {
      out.position = u.worldViewProjection * vert.p1_position;
      out.texCoord = vert.p1_uv;
  } else {
      out.position = u.worldViewProjection * vert.p2_position;
      out.texCoord = vert.p2_uv;
  }

  out.color = vert.color;
  
  return out;
}

fn median(r: f32, g: f32, b: f32) -> f32 {
    return max(min(r, g), min(max(r, g), b));
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  let msdf = textureSample(ourTexture, ourSampler, in.texCoord);
  let signed_distance = median(msdf.r, msdf.g, msdf.b) - 0.5;
  let w = clamp(signed_distance / fwidth(signed_distance) + 0.5, 0.0, 1.0);
  return in.color * w;
}