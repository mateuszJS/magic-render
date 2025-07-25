struct Vertex {
  @location(0) p0: vec4f,
  @location(1) p1: vec4f,
  @location(2) p2: vec4f,
  @location(3) color: vec4f,
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

@vertex fn vs(vert: Vertex, @builtin(vertex_index) vertex_index : u32) -> VertexOutput {
  let verticies = array<vec4f, 3>(vert.p0, vert.p1, vert.p2);
  let vertex = verticies[vertex_index];

  var out: VertexOutput;

  out.position = u.worldViewProjection * vec4f(vertex.xy, 0.0, 1.0);
  out.texCoord = vertex.zw;

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