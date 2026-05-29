fn _priv_X821b6_getColor(s: Sample) -> vec4f {
  // let signed_distance = _priv_X821b6_distance / u.texture_scale;
  var _priv_X821b6_total_color = vec4f(0);

// IMPORTANT: no spaces before custom program code
${CUSTOM_PROGRAM_CODE}
  
  return _priv_X821b6_total_color;
}

// example of custom program code:
// "program":{"code": "color=vec4f(abs(signed_distance*0.01),path_t%1,angle/6.24,1);"}
// IMPORTANT: empty lien at the end to avoid conflicts while merging next piece of code
