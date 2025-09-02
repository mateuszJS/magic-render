struct Stop {
  color: vec4f,
  offset: f32,
}

struct Uniform {
  stroke_width: f32,
  stops_count: u32,
  radius_ratio: f32, // vertical radius / horizontal radius (to create ellipse)
  padding: u32,
  center: vec2f,    // Center point of radial gradient
  destination: vec2f,    // because we have scale, the angle between center an destination is visible in the gradient!
  stops: array<Stop, 10>,
};

@group(0) @binding(0) var<uniform> u: Uniform;

fn getStrokeColor(sdf: vec4f, uv: vec2f, norm_uv: vec2f) -> vec4f {
  return vec4f(1, 1, 1, 1);
}

fn getFillColor(sdf: vec4f, world_uv: vec2f, uv: vec2f) -> vec4f {
  // Fallbacks
  if (u.stops_count == 0u) {
    return vec4f(1.0, 1.0, 1.0, 1.0);
  }
  if (u.stops_count == 1u) {
    return u.stops[0u].color;
  }

  // Calculate offset from center
  let offset = uv - u.center;

  if (length(uv - u.center) < 0.01) {
    return vec4f(1.0, 0.0, 0.0, 1.0);
  }
  if (length(uv - u.destination) < 0.01) {
    return vec4f(0.0, 0.0, 1.0, 1.0);
  }
  // return vec4f(1,1,1,1);
  
  // Calculate the horizontal radius and angle from center to destination
  let dest_offset = u.destination - u.center;
  let horizontal_radius = length(dest_offset);
  let angle = atan2(dest_offset.y, dest_offset.x);
  
  // Calculate vertical radius using the aspect ratio scale
  let vertical_radius = horizontal_radius * u.radius_ratio;
  
  // Build orthonormal basis aligned with gradient: u along destination, v perpendicular
  let u_dir = normalize(dest_offset);
  let v_dir = vec2f(-u_dir.y, u_dir.x);

  // Project offset onto this basis and normalize by radii
  let scaled_x = dot(offset, u_dir) / max(horizontal_radius, 1e-8);
  let scaled_y = dot(offset, v_dir) / max(vertical_radius, 1e-8);
  
  // Calculate normalized distance (0 at center, 1 at edge of ellipse)
  let normalized_dist = sqrt(scaled_x * scaled_x + scaled_y * scaled_y);
  let t_uv = clamp(normalized_dist, 0.0, 1.0);

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