struct Stop {
  color: vec4f,
  offset: f32,
}

struct Uniform {
  stroke_width: f32,
  stop_count: u32,
  padding: vec2f,
  center: vec2f,    // Center point of radial gradient
  destination: vec2f,    // rx, ry for elliptical gradient (rx=ry for circular)
  stops: array<Stop, 10>,
};

@group(0) @binding(0) var<uniform> u: Uniform;

fn getStrokeColor(sdf: vec4f, uv: vec2f, norm_uv: vec2f) -> vec4f {
  return vec4f(1, 1, 1, 1);
}

fn getFillColor(sdf: vec4f, world_uv: vec2f, uv: vec2f) -> vec4f {
  // Fallbacks
  if (u.stop_count == 0u) {
    return vec4f(1.0, 1.0, 1.0, 1.0);
  }
  if (u.stop_count == 1u) {
    return u.stops[0u].color;
  }

  // Calculate distance from center for radial gradient
  let offset = uv - u.center;
  
  // Handle elliptical gradient by normalizing with radii
  let rx = max(u.destination.x, 1e-8);
  let ry = max(u.destination.y, 1e-8);
  
  // Normalized distance (0 at center, 1 at edge of ellipse)
  let normalized_dist = sqrt((offset.x * offset.x) / (rx * rx) + (offset.y * offset.y) / (ry * ry));
  let t_uv = clamp(normalized_dist, 0.0, 1.0);

  // return vec4f(t_uv, t_uv, t_uv, 1.0);

  // Find lower/upper stops around t_uv using stop offsets
  let last_index = u.stop_count - 1u;
  var lower_t = -1.0;
  var lower_color = u.stops[0u].color;
  var upper_t = 2.0;
  var upper_color = u.stops[last_index].color;

  for (var i: u32 = 0u; i < u.stop_count; i = i + 1u) {
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