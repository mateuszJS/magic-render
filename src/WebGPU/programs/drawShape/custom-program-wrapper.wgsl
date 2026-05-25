fn _priv_X821b6_getColor(s: Sample) -> vec4f {
  // let signed_distance = _priv_X821b6_distance / u.texture_scale;
  var color = vec4f(1.0, 1.0, 1.0, 1.0);

  ${CUSTOM_PROGRAM_CODE}
  
  return color;
}

// example of custom program code:
// "program":{"code": "color=vec4f(abs(signed_distance*0.01),path_t%1,angle/6.24,1);"}