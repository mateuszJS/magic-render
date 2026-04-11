// let test_sdf = textureLoad(texture, vec2i(vsOut.uv));

let d = dist_to_curve;

if (d >= 0) {
  return vec4f(1, 0, 0, 1);
} else if(d >= -1) {
  return vec4f(1, 0.55, 0, 1);
} else if(d >= -2) {
  return vec4f(1, 1, 0, 1);
} else if(d >= -3) {
  return vec4f(0.4, 1, 0, 1);
} else if(d >= -4) {
  return vec4f(0.2, 0.8, 1, 1);
} else if(d >= -5) {
  return vec4f(0, 0, 1, 1);
} else if(d >= -6) {
  return vec4f(0.5, 0, 1, 1);
} else if(d >= -7) {
  return vec4f(1, 0, 1, 1);
} else {
  return vec4f(0.5);
}