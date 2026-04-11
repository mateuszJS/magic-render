const STRAIGHT_LINE_THRESHOLD = 1e10;

struct Uniform {
  placement_start: vec2f,
  placement_size: vec2f,
  initial_t: f32,
};

@group(0) @binding(0) var source_tex: texture_2d<f32>;
@group(0) @binding(1) var<uniform> u: Uniform;
@group(0) @binding(2) var<storage, read> curves: array<vec2f>;

struct VSOutput {
  @builtin(position) position: vec4f,
};

const vertex_list = array<vec2f, 6>(
  vec2f(-1.0, -1.0), vec2f( 1.0, -1.0), vec2f(-1.0,  1.0),
  vec2f(-1.0,  1.0), vec2f( 1.0, -1.0), vec2f( 1.0,  1.0),
);

@vertex fn vs(@builtin(vertex_index) idx: u32) -> VSOutput {
  return VSOutput(vec4f(vertex_list[idx], 0.0, 1.0));
}

struct FSOutput {
  @location(0) color: f32,
  @builtin(frag_depth) depth: f32,
};

@fragment fn fs(vsOut: VSOutput) -> FSOutput {
  let dest_center = vsOut.position.xy;
  let local = (dest_center - u.placement_start) / u.placement_size;
  let source_size = vec2f(textureDimensions(source_tex));
  let source_sample_pos = local * source_size;
  let source_texel = textureLoad(source_tex, vec2u(source_sample_pos), 0);

  let sanitized_t = abs(source_texel.r) - 1.0;
  let closest_curve_point = g_to_bezier_pos(sanitized_t);
  let distance = length(dest_center - closest_curve_point);
  let scaled_dist = 0.5 + sign(source_texel.r) * distance / 1000;//max(source_size.x, source_size.y);

  return FSOutput(
    (1.0 + u.initial_t + sanitized_t) * sign(source_texel.r),
    scaled_dist,
  );
}

fn bezier_point(curve: CubicBezier, t: f32) -> vec2f {
  let t2 = t * t;
  let t3 = t2 * t;
  let one_minus_t = 1.0 - t;
  let one_minus_t2 = one_minus_t * one_minus_t;
  let one_minus_t3 = one_minus_t2 * one_minus_t;

  return curve.p0 * one_minus_t3 +
         3.0 * curve.p1 * t * one_minus_t2 +
         3.0 * curve.p2 * t2 * one_minus_t +
         curve.p3 * t3;
}


struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};


fn g_to_bezier_pos(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let local_t = fract(global_t);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );

  let is_straight_line = curve.p1.x > STRAIGHT_LINE_THRESHOLD;
  if (is_straight_line) {
    return mix(curve.p0, curve.p3, local_t);
  }

  return bezier_point(curve, local_t);
}