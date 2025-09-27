struct Uniform {
  placement_start: vec2f,
  placement_size: vec2f,
};

@group(0) @binding(0) var destination_tex: texture_storage_2d<rgba32float, write>;
@group(0) @binding(1) var source_tex: texture_storage_2d<rgba32float, read>;
@group(0) @binding(2) var depth_tex: texture_storage_2d<r32float, read_write>;
@group(0) @binding(3) var<uniform> u: Uniform;

@compute @workgroup_size(1) fn cs(
  @builtin(global_invocation_id) id : vec3u
)  {
  let texel_pos = vec2f(id.xy) + vec2f(0.5);

  let dest_pos = vec2i(u.placement_start + texel_pos);
  if (any(dest_pos < vec2i(0)) || any(dest_pos >= vec2i(textureDimensions(destination_tex)))) {
    return;
  }

  let depth = textureLoad(depth_tex, dest_pos).r;
  let ratio_source_tex_to_placement = vec2f(textureDimensions(source_tex)) / u.placement_size; // texture doesn't to be same size as placement_size!
  let source_texel = getSample(texel_pos * ratio_source_tex_to_placement);

  if (source_texel.r > depth){
    textureStore(destination_tex, dest_pos, source_texel);
    textureStore(depth_tex, dest_pos, vec4f(source_texel.r));
  }
}

fn getSample(pos: vec2f) -> vec4f {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let p00 = vec2u(floor_pos);
  let p10 = vec2u(floor_pos + vec2f(1.0, 0.0));
  let p01 = vec2u(floor_pos + vec2f(0.0, 1.0));
  let p11 = vec2u(floor_pos + vec2f(1.0, 1.0));

  let c00 = textureLoad(source_tex, p00);
  let c10 = textureLoad(source_tex, p10);
  let c01 = textureLoad(source_tex, p01);
  let c11 = textureLoad(source_tex, p11);

  let top = mix(c00, c10, fract_pos.x);
  let bottom = mix(c01, c11, fract_pos.x);

  return mix(top, bottom, fract_pos.y);
}