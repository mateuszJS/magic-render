if (sdf.r >= 0) {
  return vec4f(1, 0, 0, 1);
} else if(sdf.r >= -1) {
  return vec4f(1, 0.5, 0, 1);
} else if(sdf.r >= -2) {
  return vec4f(1, 1, 0, 1);
} else if(sdf.r >= -3) {
  return vec4f(0.4, 1, 0, 1);
} else if(sdf.r >= -4) {
  return vec4f(0.2, 0.8, 1, 1);
} else if(sdf.r >= -5) {
  return vec4f(0, 0, 1, 1);
} else if(sdf.r >= -6) {
  return vec4f(0.5, 0, 1, 1);
} else if(sdf.r >= -7) {
  return vec4f(1, 0, 1, 1);
} else {
  return vec4f(0.5);
}