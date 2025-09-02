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
  
  // Vector from center to destination encodes major axis direction and length
  let dest_offset = u.destination - u.center;
  let hr = length(dest_offset);
  let inv_hr = 1.0 / max(hr, 1e-8);
  let inv_vr = inv_hr / max(u.radius_ratio, 1e-8);

  // Orthonormal basis aligned with gradient: u along destination, v perpendicular
  let u_dir = dest_offset * inv_hr;              // normalized major axis
  let v_dir = vec2f(-u_dir.y, u_dir.x);         // normalized minor axis

  // Project offset into this basis and normalize by radii
  let scaled_x = dot(offset, u_dir) * inv_hr;   // == dot(offset, dest_offset) * inv_hr^2
  let scaled_y = dot(offset, v_dir) * inv_vr;   // divide by vertical radius
  
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