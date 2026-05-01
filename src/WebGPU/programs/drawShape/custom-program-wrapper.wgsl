struct Uniforms {
  program_id: u32, // not useful here, but kept for alignment
  dist_start: f32,
  dist_end: f32,
  sdf_scale: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn getColor(_distance_X821b6_private: f32, path_t: f32, angle: f32, world_uv: vec2f, uv: vec2f) -> vec4f {
  let signed_distance = _distance_X821b6_private / u.sdf_scale;
  var color = vec4f(1.0, 1.0, 1.0, 1.0);

  ${CUSTOM_PROGRAM_CODE}
  
  return color;
}

// example of custom program code:
// "program":{"code": "color=vec4f(abs(signed_distance*0.01),path_t%1,angle/6.24,1);"}