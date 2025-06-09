struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: f32,
};

struct Uniforms {
  worldViewProjection: mat4x4f,
};

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) @interpolate(flat) id: f32
};

@group(0) @binding(0) var<uniform> u: Uniforms;

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;
  out.position = u.worldViewProjection * vert.position;
  out.id = vert.id;
  
  return out;
}

@fragment fn fs(in: VertexOutput) -> @location(0) u32 {
  return u32(in.id);
}

