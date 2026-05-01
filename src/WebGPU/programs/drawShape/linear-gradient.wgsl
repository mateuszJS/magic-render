struct Stop {
  color: vec4f,
  offset: f32,
}

struct Uniform {
  dist_start: f32,
  dist_end: f32,
  stops_count: u32,
  padding: u32, // Padding for alignment
  start: vec2f,
  end: vec2f,
  stops: array<Stop, 10>,
};

@group(0) @binding(0) var<uniform> u: Uniform;


fn getColor(_distance_X821b6_private: f32, t: f32, angle: f32, world_uv: vec2f, uv: vec2f) -> vec4f {
  // Fallbacks
  if (u.stops_count == 0u) {
    return vec4f(1.0, 1.0, 1.0, 1.0);
  }
  if (u.stops_count == 1u) {
  return u.stops[0u].color;
  }

  // Gradient axis given by start -> end in uv space
  let dir = u.end - u.start;
  let len2_raw = dot(dir, dir);
  let len2 = max(len2_raw, 1e-8);

  // Project current uv to axis; get normalized parameter t in [0, 1]
  var t_uv: f32;
  if (len2_raw < 1e-7) {
    // Degenerate axis: fall back to horizontal gradient across world_uv.x
    t_uv = clamp(uv.x, 0.0, 1.0);
  } else {
    // project vector with uv positon onto gradient vector to see "how far" is the pixel along the gradient line
    // len2 to tonalize
    t_uv = clamp(dot(uv - u.start, dir) / len2, 0.0, 1.0);
  }

  // Find lower/upper stops around t_uv using stop offsets
  let last_index = u.stops_count - 1u;
  var lower_t = -1.0;
  var lower_color = u.stops[0u].color;
  var upper_t = 2.0;
  var upper_color = u.stops[last_index].color;

  for (var i: u32 = 0u; i < u.stops_count; i = i + 1u) {
    let ti = clamp(u.stops[i].offset, 0.0, 1.0);
    if (ti <= t_uv && ti > lower_t) {
      lower_t = ti;
      lower_color = u.stops[i].color;
    }
    if (ti >= t_uv && ti < upper_t) {
      upper_t = ti;
      upper_color = u.stops[i].color;
    }
  }

  // Boundaries: if t is before the first stop or after the last stop
  if (lower_t < 0.0) {
    return upper_color; // before first stop
  }
  if (upper_t > 1.5) {
    return lower_color; // after last stop
  }

  // Interpolate between the two surrounding stops
  let denom = max(upper_t - lower_t, 1e-8);
  let a = clamp((t_uv - lower_t) / denom, 0.0, 1.0);
  return mix(lower_color, upper_color, a);
}