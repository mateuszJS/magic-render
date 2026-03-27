struct Uniform {
  placement_start: vec2f,
  placement_size: vec2f,
};

@group(0) @binding(0) var destination_tex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(1) var source_tex: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var depth_tex: texture_storage_2d<r32float, read_write>;
@group(0) @binding(3) var<uniform> u: Uniform;

@compute @workgroup_size($WORKING_GROUP_SIZE) fn cs(
  @builtin(global_invocation_id) id : vec3u
)  {
  if (any(u.placement_size <= vec2f(0.0))) {
    return;
  }

  let placement_min = floor(u.placement_start);
  let placement_max = ceil(u.placement_start + u.placement_size);

  let dest_pos = vec2i(placement_min) + vec2i(id.xy);

  if (any(vec2f(dest_pos) >= placement_max)) {
    return;
  }

  let dest_dims = vec2i(textureDimensions(destination_tex));
  if (any(dest_pos < vec2i(0)) || any(dest_pos >= dest_dims)) {
    return;
  }

  let dest_center = vec2f(dest_pos) + vec2f(0.5);
  let local = (dest_center - u.placement_start) / u.placement_size;

  if (any(local < vec2f(0.0)) || any(local >= vec2f(1.0))) {
    return;
  }

  let source_size = vec2f(textureDimensions(source_tex));
  let source_sample_pos = local * source_size;
  let source_texel = getSampleSource(source_sample_pos);
  let scale = source_size / u.placement_size;
  let scaled_dist = source_texel.r / scale.x; // we assume all sizes keeps their ratio width / height, so we can use .x or .y here
  let depth = textureLoad(depth_tex, dest_pos).r;

  if (scaled_dist > depth) {
    textureStore(destination_tex, dest_pos, vec4f(scaled_dist, source_texel.g, source_texel.b, source_texel.a));
    textureStore(depth_tex, dest_pos, vec4f(scaled_dist));
  }
}

fn getSampleSource(pos: vec2f) -> vec4f {
  let source_dims_u = textureDimensions(source_tex);
  let source_dims_i = vec2i(source_dims_u);

  let clamped_pos = clamp(pos, vec2f(0.5), vec2f(source_dims_u) - vec2f(0.5));
  let base_pos = clamped_pos - vec2f(0.5);

  let floor_pos = vec2i(floor(base_pos));
  let fract_pos = base_pos - vec2f(floor_pos);

  let p00 = vec2u(clamp(floor_pos, vec2i(0), source_dims_i - vec2i(1)));
  let p10 = vec2u(clamp(floor_pos + vec2i(1, 0), vec2i(0), source_dims_i - vec2i(1)));
  let p01 = vec2u(clamp(floor_pos + vec2i(0, 1), vec2i(0), source_dims_i - vec2i(1)));
  let p11 = vec2u(clamp(floor_pos + vec2i(1, 1), vec2i(0), source_dims_i - vec2i(1)));

  let c00 = textureLoad(source_tex, p00);
  let c10 = textureLoad(source_tex, p10);
  let c01 = textureLoad(source_tex, p01);
  let c11 = textureLoad(source_tex, p11);

  let top = mix(c00, c10, fract_pos.x);
  let bottom = mix(c01, c11, fract_pos.x);

  return mix(top, bottom, fract_pos.y);
}