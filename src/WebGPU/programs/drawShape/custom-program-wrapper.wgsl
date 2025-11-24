fn getColor(sdf: vec4f, world_uv: vec2f, uv: vec2f) -> vec4f {
  let signed_distance = sdf.r;
  let path_t = sdf.g;
  let angle = sdf.b;
  var color = vec4f(1.0, 1.0, 1.0, 1.0);

  ${CUSTOM_PROGRAM_CODE}
  
  return color;
}