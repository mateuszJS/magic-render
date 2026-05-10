struct Vertex {
  @location(0) position: vec4f,
  @location(1) id: vec4u,
};

struct Uniforms {
  dist_start: f32,
  dist_end: f32,
};

@group(0) @binding(0) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(1) var<uniform> u: Uniforms;
@group(0) @binding(2) var texture: texture_2d<f32>;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;

struct VertexOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) @interpolate(flat) id: vec4u
};

@vertex fn vs(vert: Vertex) -> VertexOutput {
  var out: VertexOutput;

  out.position = camera_projection * vec4f(vert.position.xy, 0.0, 1.0);
  out.id = vert.id;

  let size = textureDimensions(texture);
  out.uv = vert.position.zw * vec2f(size);

  return out;
}

@fragment fn fs(vsOut: VertexOutput) -> @location(0) vec4u {
  let t = textureLoad(texture, vec2u(vsOut.uv), 0).r;
  let curve_pos = t_to_pos(t);
  let curve_tan = t_to_tan(t);
  let is_inside = get_is_inside(vsOut.uv, t, curve_tan, curve_pos);

  let distance = length(curve_pos - vsOut.uv);
  let signed_distance = distance * is_inside;

  if (signed_distance > u.dist_start || signed_distance < u.dist_end) {
    discard;
  }

  return vsOut.id;
}
