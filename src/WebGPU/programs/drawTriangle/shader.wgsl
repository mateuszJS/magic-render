struct Vertex {
  @location(0) position: vec4f,
  @location(1) color: vec4f,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) color: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  out.position = u.worldViewProjection * vert.position;
  out.color = vert.color;
  
  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) vec4f {
  return in.color;
}
