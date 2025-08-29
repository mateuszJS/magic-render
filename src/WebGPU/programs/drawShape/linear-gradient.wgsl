
struct Uniforms {
  stroke_width: f32,
  stop_count: u32,
  stop_positions: array<vec4f, 10>,
  stop_colors: array<vec4f, 10>,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

fn getStrokeColor(sdf: vec4f, uv: vec2f) -> vec4f {
  return vec4f(1, 1, 1, 1);
}

fn getFillColor(sdf: vec4f, uv: vec2f) -> vec4f {
  // Fallbacks
  if (u.stop_count == 0u) {
    return vec4f(1, 1, 1, 1);
  }
  if (u.stop_count == 1u) {
    return u.stop_colors[0u];
  }

  // Define gradient axis as the line from first to last stop position (in uv space)
  let first_pos = u.stop_positions[0u].xy;
  let last_index = u.stop_count - 1u;
  let last_pos = u.stop_positions[last_index].xy;
  let dir = last_pos - first_pos;
  let len2 = max(dot(dir, dir), 1e-8);

  // Project a point to the axis, return normalized t in [0,1]
  let t_uv = clamp(dot(uv - first_pos, dir) / len2, 0.0, 1.0);

  // Scan all stops to find the immediate lower and upper stops around t_uv
  var lower_t = -1.0;
  var lower_color = u.stop_colors[0u];
  var upper_t = 2.0;
  var upper_color = u.stop_colors[last_index];

  for (var i: u32 = 0u; i < u.stop_count; i = i + 1u) {
    let sp = u.stop_positions[i].xy;
    let ti = clamp(dot(sp - first_pos, dir) / len2, 0.0, 1.0);
    let c = u.stop_colors[i];
    if (ti <= t_uv && ti > lower_t) {
      lower_t = ti;
      lower_color = c;
    }
    if (ti >= t_uv && ti < upper_t) {
      upper_t = ti;
      upper_color = c;
    }
  }

  // Handle boundaries
  if (t_uv <= lower_t) {
    return lower_color;
  }
  if (t_uv >= upper_t) {
    return upper_color;
  }

  // Interpolate between the two surrounding stops
  let denom = max(upper_t - lower_t, 1e-8);
  let a = clamp((t_uv - lower_t) / denom, 0.0, 1.0);
  return mix(lower_color, upper_color, a);
}