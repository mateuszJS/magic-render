struct Uniform {
  placement_start: vec2f,
  placement_size: vec2f,
  initial_t: f32,
};

@group(0) @binding(0) var source_tex: texture_2d<f32>;
@group(0) @binding(1) var<uniform> u: Uniform;
@group(0) @binding(2) var<storage, read> curves: array<vec2f>;

struct VSOutput {
  @builtin(position) position: vec4f,
};

const vertex_list = array<vec2f, 6>(
  vec2f(-1.0, -1.0), vec2f( 1.0, -1.0), vec2f(-1.0,  1.0),
  vec2f(-1.0,  1.0), vec2f( 1.0, -1.0), vec2f( 1.0,  1.0),
);

@vertex fn vs(@builtin(vertex_index) idx: u32) -> VSOutput {
  return VSOutput(vec4f(vertex_list[idx], 0.0, 1.0));
}

struct FSOutput {
  @location(0) color: f32,
  @builtin(frag_depth) depth: f32,
};

@fragment fn fs(vsOut: VSOutput) -> FSOutput {
  let uv = vsOut.position.xy;
  let local = (uv - u.placement_start) / u.placement_size;
  let source_size = vec2f(textureDimensions(source_tex));
  let source_sample_pos = local * source_size;
  let source_texel = textureLoad(source_tex, vec2u(source_sample_pos), 0);

  let closest_curve_point = t_to_pos(source_texel.r);
  let distance = length(uv - closest_curve_point);
  let scaled_dist = 0.5 - sign(source_texel.r) * distance / 100;//max(source_size.x, source_size.y);

  return FSOutput(
    (u.initial_t + source_texel.r) * sign(source_texel.r),
    scaled_dist,
  );
}
