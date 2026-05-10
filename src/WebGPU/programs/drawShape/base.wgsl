
const EPSILON = 1e-10;
const PI = 3.141592653589793;
const TAU = 2 * PI;

// Background texels store ≈ −3.4e38; their fwidth is enormous. Anything larger
// than this is treated as "background derivative" and zeroed.
const FWIDTH_VALID_LIMIT = 3.402823466e+10;

const BILINEAR_ARC_THRESHOLD = 1.5; // avoid blending texels that have arc further than BILINEAR_ARC_THRESHOLD away
const BILINEAR_ANGLE_DOT_THRESHOLD = -0.059016994; // cos(0.5 * PI)
// avoid blending texels which angle diff with nearest neighbour angle is bigger than 0.5*PI

// Number of stored arc-length, max-distances samples per curve (at t = 0, 1/4, 2/4, 3/4).
const EXTERNAL_BUFFER_SAMPLES_PER_CURVE = 4.0;


struct Vertex {
  @location(0) position: vec4f,
};

struct BaseUniform {
  texture_size: vec2f, // = vec2f(textureDimensions(texture)),
  total_arc_len: f32, // arc_lengths[length-1], Saves one storage-buffer load.
  num_curves: u32, // arrayLength(&curves) / 4. Avoids the runtime length query,
  debug_scale: f32, // multiplier applied to the debug-overlay grid cell,
  debug_type: u32 // 0u -> no debug, 1u -> show arrows(useful for angles), 2u -> show digits
};

@group(0) @binding(1) var texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;
@group(0) @binding(4) var<storage, read> arc_lengths: array<f32>;
@group(0) @binding(5) var<uniform> base_u: BaseUniform;
@group(0) @binding(6) var<storage, read> max_distances: array<f32>;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) norm_uv: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  return VSOutput(
    camera_projection * vec4f(vert.position.xy, 0.0, 1.0),
    vert.position.zw * base_u.texture_size,
    vert.position.zw,
  );
}

// One cached neighbour (a single texel near the fragment) plus all the
// per-texel quantities we'll need. Computed once in loadNeighbour() so the
// downstream nearest-pick / corner / blend stages never reload `curves[]`.
struct Neighbour {
  t: f32,        // texel's stored g (fract = local t, floor = curve index)
  pos: vec2f,    // closest point on the curve, according to this particular texel
  tan: vec2f,    // UNIT tangent at g  (g_to_bezier_tangent always normalises)
  arc: f32,      // raw cumulative arc length at g (pre-seam-wrap)
  debug_probe: f32,
};

// Per-neighbour Newton refinement. The baker stored `t` as the
// closest-point t on the path to THIS texel's centre. For a fragment at
// `pos`, the closest point on the SAME curve segment is found by walking
// `t` toward `pos` with one Newton step. Each neighbour therefore
// reports a `pos` / `tan` / `arc` aligned to the fragment, not to the
// stale texel-centre value the baker chose.
fn loadNeighbour(coord: vec2u, pos: vec2f) -> Neighbour {
  let raw_t = textureLoad(texture, coord, 0).r;

  // combiendSdf have all texels filled with -3.4e38 on the start, so we filter those out
  // and let other guards handle this case
  let is_valid = raw_t >= 0.0 && raw_t < f32(base_u.num_curves);

  var redefined_t = raw_t;
  // maybe we should do it only if distance is smaller than 1-2 texels?
  if (is_valid) {
    // Redefind on neighbour level fixes harsh edges(see ./artifacts/harsh edges.png) + a bit distance improvement
    // BUT messes up all the distance related things! And also is not needed for angle!
    let refined = refine_curve_pos(pos, raw_t);
    redefined_t = refined.t;
  }

  let debug_probe = 0.0;

  return Neighbour(
    redefined_t,
    t_to_pos(redefined_t),
    t_to_tan(redefined_t),
    t_to_arc(redefined_t),
    debug_probe,
  );
}

// Inverse arc-length map: arc length → t (curve_idx + local_t).
fn arc_to_t(arc: f32) -> f32 {
  let len = arrayLength(&arc_lengths);
  // Empty / single-entry buffer: no curves to look up. Return start.
  if (len < 2u) { return 0.0; }
  var lo = 0u;
  var hi = len - 1u;
  while (lo + 1u < hi) {
    let mid = (lo + hi) / 2u;
    if (arc_lengths[mid] <= arc) { lo = mid; } else { hi = mid; }
  }
  let arc_lo = arc_lengths[lo];
  let arc_hi = arc_lengths[hi];
  let frac = select(0.0, (arc - arc_lo) / (arc_hi - arc_lo), arc_hi > arc_lo);
  // lo index maps to: curve = lo/4, quarter = lo%4
  let ci = lo / u32(EXTERNAL_BUFFER_SAMPLES_PER_CURVE);
  let quarter = lo % u32(EXTERNAL_BUFFER_SAMPLES_PER_CURVE);
  let local_t = (f32(quarter) + frac) / EXTERNAL_BUFFER_SAMPLES_PER_CURVE;

  let result = f32(ci) + local_t;
  // Clamp to just inside the last segment so floor(result) < num_curves and
  // fract != 0 (i.e. not interpreted as a baker-snapped junction either).
  let max_safe = f32(base_u.num_curves) - 1e-5;
  return min(result, max_safe);
}

fn getNearestNeighbour(pos: vec2f, n00: Neighbour, n01: Neighbour, n10: Neighbour, n11: Neighbour) -> Neighbour {
  let d00 = max(1e-6, length(n00.pos - pos));
  let d10 = max(1e-6, length(n10.pos - pos));
  let d01 = max(1e-6, length(n01.pos - pos));
  let d11 = max(1e-6, length(n11.pos - pos));

  // Pick the nearest neighbour. select() in WGSL only works on scalars/vectors
  // / matrices — not user structs — so we pick each field individually. The
  // compiler folds these to a single underlying selection.
  let prefer_top  = min(d01, d11) < min(d00, d10);
  let prefer_x_lo = d10 < d00;
  let prefer_x_hi = d11 < d01;
  let nearest_g   = select(select(n00.t,   n10.t,   prefer_x_lo), select(n01.t,   n11.t,   prefer_x_hi), prefer_top);
  let nearest_pos = select(select(n00.pos, n10.pos, prefer_x_lo), select(n01.pos, n11.pos, prefer_x_hi), prefer_top);
  let nearest_tan = select(select(n00.tan, n10.tan, prefer_x_lo), select(n01.tan, n11.tan, prefer_x_hi), prefer_top);
  let nearest_arc = select(select(n00.arc, n10.arc, prefer_x_lo), select(n01.arc, n11.arc, prefer_x_hi), prefer_top);
  let nearest_debug_probe = select(select(n00.debug_probe, n10.debug_probe, prefer_x_lo), select(n01.debug_probe, n11.debug_probe, prefer_x_hi), prefer_top);

  return Neighbour(
    nearest_g,
    nearest_pos,
    nearest_tan,
    nearest_arc,
    nearest_debug_probe,
  );
}

const WALK_ARC_SOFTNESS_FACTOR: f32 = 0.3;
const WALK_ARC_SAMPLES: i32 = 32;
const WALK_ARC_WINDOW_FACTOR: f32 = 3.0;

// Samples t across neighbour arcs and blends their angles & max distance together

struct MoveAvgResult {
  angle: f32,
  max_distance: f32,
};

fn getMovingAvg(pos: vec2f, arc_primary: f32, d_min: f32) -> MoveAvgResult {
  let total = base_u.total_arc_len;
  let n_f = f32(WALK_ARC_SAMPLES);
  let softness = max(WALK_ARC_SOFTNESS_FACTOR * d_min, 1e-6);
  let inv_softness = 1.0 / softness;
  let half_win = WALK_ARC_WINDOW_FACTOR * d_min;

  var sum_angle = vec2f(0.0);
  var sum_max_distance = 0.0;
  var sum_weight = 0.0;


  for (var i = 0; i < WALK_ARC_SAMPLES; i = i + 1) {
    let arc = clamp(arc_primary - half_win + (f32(i) + 0.5) * (2.0 * half_win) / n_f, 0.0, total);
    let t = arc_to_t(arc);
    let p = t_to_pos(t);

    let to_curve = p - pos;
    let d = length(to_curve);

    if (d < 1e-6) { continue; }

    let w = exp(-(d - d_min) * inv_softness);

    sum_angle = sum_angle + (to_curve / d) * w;
    sum_max_distance = sum_max_distance + t_to_max_distance(t) * w;
    sum_weight       = sum_weight + w;
  }

  let avg_max_distance = select(
    t_to_max_distance(arc_to_t(arc_primary)),
    sum_max_distance / sum_weight,
    sum_weight > 1e-6
  );

  return MoveAvgResult(atan2(sum_angle.y, sum_angle.x), avg_max_distance);
}

struct Sample {
  t: f32,
  signed_distance: f32,
  angle: f32,
  blend_angle: f32,
  norm_distance: f32,
  debug_probe: f32,
};

fn getSample(pos: vec2f) -> Sample {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let max_coord = vec2i(base_u.texture_size) - vec2i(1, 1);

  let p00 = vec2u(clamp(vec2i(floor_pos),                   vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  let n00 = loadNeighbour(p00, pos);
  let n10 = loadNeighbour(p10, pos);
  let n01 = loadNeighbour(p01, pos);
  let n11 = loadNeighbour(p11, pos);
  let nNearest = getNearestNeighbour(pos, n00, n10, n01, n11);


  var debug_probe = nNearest.arc;

  let is_inside = get_is_inside(pos, nNearest.t, nNearest.tan, nNearest.pos);

  // ---------------------------------------------------------------------------
  // Filter & bilinear-blend the four neighbours' arc-length values.
  //   - Drop a neighbour whose tangent points nearly opposite to nearest's
  //     (avoids smearing across folds): cheap dot-product test on UNIT tangents.
  //   - Drop a neighbour whose arc length is too far from nearest's (avoids
  //     smearing across distant parts of the path).
  //   - Wrap each neighbour's arc length to the period closest to nearest_arc
  //     so the start/end seam blends smoothly.
  // ---------------------------------------------------------------------------

  let inv_arc = select(0.0, 1.0 / base_u.total_arc_len, base_u.total_arc_len > 1e-8); // I'm not sure if total_arc_len can ever be that small

  // without abs() we prodcue extremly small neagtive value, like -0.000000001, and that negative value messes up logic later
  let arc00 = n00.arc + base_u.total_arc_len * round(abs(nNearest.arc - n00.arc) * inv_arc);
  let arc10 = n10.arc + base_u.total_arc_len * round(abs(nNearest.arc - n10.arc) * inv_arc);
  let arc01 = n01.arc + base_u.total_arc_len * round(abs(nNearest.arc - n01.arc) * inv_arc);
  let arc11 = n11.arc + base_u.total_arc_len * round(abs(nNearest.arc - n11.arc) * inv_arc);

  let arc_diff_00 = abs(arc00 - nNearest.arc);
  let arc_diff_10 = abs(arc10 - nNearest.arc);
  let arc_diff_01 = abs(arc01 - nNearest.arc);
  let arc_diff_11 = abs(arc11 - nNearest.arc);

  // Tangents are unit-length, so dot == cos(angle).
  let cos00 = dot(n00.tan, nNearest.tan);
  let cos10 = dot(n10.tan, nNearest.tan);
  let cos01 = dot(n01.tan, nNearest.tan);
  let cos11 = dot(n11.tan, nNearest.tan);

  // multiplied by nearest_sign because is_angle_near has only good effects when inside the shape
  let keep00 = arc_diff_00 < BILINEAR_ARC_THRESHOLD && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep01 = arc_diff_01 < BILINEAR_ARC_THRESHOLD && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep10 = arc_diff_10 < BILINEAR_ARC_THRESHOLD && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep11 = arc_diff_11 < BILINEAR_ARC_THRESHOLD && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD;

  let bili_dist00 = (1.0 - fract_pos.x) * (1.0 - fract_pos.y);
  let bili_dist01 = (1.0 - fract_pos.x) * fract_pos.y;
  let bili_dist10 = fract_pos.x         * (1.0 - fract_pos.y);
  let bili_dist11 = fract_pos.x         * fract_pos.y;

  let w00 = select(0.0, bili_dist00, keep00);
  let w01 = select(0.0, bili_dist01, keep01);
  let w10 = select(0.0, bili_dist10, keep10);
  let w11 = select(0.0, bili_dist11, keep11);

  let total_w = w00 + w10 + w01 + w11;
  // Fallback to nearest when all neighbours are filtered (e.g. very sharp corner).
  let arc_blended = select(
    nNearest.arc,
    (arc00 * w00 + arc10 * w10 + arc01 * w01 + arc11 * w11) / total_w,
    total_w > 1e-6
  );
  let _blended_global_t = arc_to_t(arc_blended);

  let refined_primary = refine_curve_pos(pos, _blended_global_t);
  let blended_global_t = refined_primary.t;

  let refined_blended_global_t = refine_curve_pos(pos, blended_global_t).t; // looks good for distance
  let abs_distance = length(pos - t_to_pos(refined_blended_global_t));

  let move_avg_results = getMovingAvg(pos, arc_blended, abs_distance);
  let blend_angle = move_avg_results.angle;

  let curve_pos = t_to_pos(refined_blended_global_t);
  // Negative inside, positive outside, in pixel-space units (see header).
  let signed_distance = length(curve_pos - pos) * is_inside;
  let angle = atan2(curve_pos.y - pos.y, curve_pos.x - pos.x);
  let norm_distance = clamp(abs(signed_distance) / move_avg_results.max_distance, 0.0, 1.0);

  debug_probe = nNearest.arc - n00.arc;

  return Sample(
    refined_blended_global_t,
    signed_distance,
    angle,
    blend_angle,
    norm_distance,
    debug_probe,
  );
}

// Forward arc-length map: g → cumulative arc length along the path.
fn t_to_arc(global_t: f32) -> f32 {
  let curve_index = u32(global_t);
  let local_t = fract(global_t);

  // Which quarter of the curve are we in? [0..3]
  let quarter_f = local_t * EXTERNAL_BUFFER_SAMPLES_PER_CURVE;
  let quarter = u32(floor(quarter_f));
  let frac = fract(quarter_f);

  let lower_idx = curve_index * u32(EXTERNAL_BUFFER_SAMPLES_PER_CURVE) + quarter;
  let upper_idx = lower_idx + 1u;

  // Buffer is sized 4*N+1 and callers pass g < N, so upper_idx ≤ 4N is in
  // bounds. The clamps below are defensive in case of an unexpected overflow
  // (e.g. a caller passing exactly N or NaN-driven indexing).
  let max_idx = arrayLength(&arc_lengths) - 1u;
  let safe_lower = min(lower_idx, max_idx);
  let safe_upper = min(upper_idx, max_idx);
  return mix(arc_lengths[safe_lower], arc_lengths[safe_upper], frac);
}

// Normalises the fragment's signed `distance` from the boundary into a
// clamped 0..1 ratio of "how deep is this fragment compared to the largest
// inscribed disk tangent here". `max_distances` stores, per sample point
// (4*N + 1 samples, same layout as `arc_lengths`), the radius of the
// medial-axis circle inscribed at that sample — i.e. the distance from
// the boundary point to the medial axis along its inward normal.
//
// We interpolate that radius at `global_t` with the same quarter-sample
// scheme as `t_to_arc`, then divide. No boundary-flip trick is needed:
// the value at a shared boundary index is the medial radius of a single
// physical point, single-valued at smooth joins and roughly the same on
// both sides at corners — close enough for a normalisation factor.
//
// `distance` is signed (positive inside, negative outside per the
// is_inside convention in getSample); the clamp pulls exterior fragments
// down to 0 and fragments past the medial axis up to 1.
fn t_to_max_distance(global_t: f32) -> f32 {
  let curve_index = u32(global_t);
  let local_t = fract(global_t);

  let quarter_f = local_t * EXTERNAL_BUFFER_SAMPLES_PER_CURVE;
  let quarter = u32(floor(quarter_f));
  let frac = fract(quarter_f);

  let lower_idx = curve_index * u32(EXTERNAL_BUFFER_SAMPLES_PER_CURVE) + quarter;
  let upper_idx = lower_idx + 1u;

  let max_idx = arrayLength(&max_distances) - 1u;
  let safe_lower = min(lower_idx, max_idx);
  let safe_upper = min(upper_idx, max_idx);

  let max_at_t = mix(max_distances[safe_lower], max_distances[safe_upper], frac);
  return max(max_at_t, 1e-6);
}

// Refines the nearest-curve-point estimate from bilinear t interpolation by
// doing one Newton-Raphson step minimising |bezier(t) - pos|². For straight
// lines, computes the exact projection.
//
// Local-t upper bound is 1 − ε rather than 1 because returning exactly
// `f32(idx) + 1.0` flips the segment encoding: `floor(idx + 1.0) = idx + 1`
// and `fract(idx + 1.0) = 0`, so downstream lookups (global_t_to_position /
// _tangent / _arc) read curve idx+1, t=0. For curves in the middle of a
// path that's the next segment along the same path and the tangent
// happens to be continuous; for the last curve of any path it's the
// first curve of a *different* path, and the wrong tangent gives a wrong
// half-plane sign — visible as stray inside/outside pixels in the inner
// counters of letters like "e", "q", "o".
fn refine_curve_pos(pos: vec2f, global_t: f32) -> Refined {
  let idx = u32(global_t);
  let t = fract(global_t);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  // Just-under-1 upper clamp, see header note above.
  let MAX_LOCAL_T = 1.0 - 1e-5;

  if (is_straight_line_marker(p1)) {
    let line_vec = p3 - p0;
    let len_sq = dot(line_vec, line_vec);
    // Defensive: zero-length line ⇒ refined_t = 0, return endpoint.
    let refined_t = select(0.0,
                           clamp(dot(pos - p0, line_vec) / len_sq, 0.0, MAX_LOCAL_T),
                           len_sq > 1e-12);
    return Refined(
      mix(p0, p3, refined_t),
      f32(idx) + refined_t
    );
  }

  let curve = CubicBezier(p0, p1, p2, p3);
  let orig_pos = bezier_point(curve, t);
  let mt = 1.0 - t;
  let dp  = 3.0 * (mt * mt * (p1 - p0) + 2.0 * mt * t * (p2 - p1) + t * t * (p3 - p2));
  let ddp = 6.0 * (mt * (p2 - 2.0 * p1 + p0) + t * (p3 - 2.0 * p2 + p1));
  let diff = orig_pos - pos;
  // Full Newton denominator (includes curvature term) prevents overshooting on
  // the concave side of high-curvature curves.
  let df = dot(dp, dp) + dot(diff, ddp);
  let refined_t = clamp(t - select(0.0, dot(diff, dp) / df, abs(df) > 1e-8), 0.0, MAX_LOCAL_T);
  let refined_pos = bezier_point(curve, refined_t);

  // Only accept the refined position if it's strictly closer.
  let condition = dot(refined_pos - pos, refined_pos - pos) < dot(orig_pos - pos, orig_pos - pos);
  let best_pos = select(orig_pos, refined_pos, condition);
  let best_t = select(global_t, f32(idx) + refined_t, condition);

  return Refined(best_pos, best_t);
}

struct Refined {
  pos: vec2f,
  t: f32
};

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let uv = vsOut.uv;
  let s = getSample(uv);

  ${TEST}

  let dist_derivative = length(fwidth(uv));
  // Background derivatives are huge (≈ 3.4e38) — clamp those to 0 so we don't
  // smear the AA band into "this whole pixel is on a boundary".
  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT);
  let alpha_smooth_factor = max(safe_dist_derivative * 0.5, EPSILON);

  // TODO: should this be done like this? Currently distance is not the only thing that impact boundaries of the output.
  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, s.signed_distance);
  let outer_alpha = smoothstep(u.dist_end   - alpha_smooth_factor, u.dist_end   + alpha_smooth_factor, s.signed_distance);
  let alpha = outer_alpha - inner_alpha;

  var color = getColor(s.signed_distance, s.t, s.blend_angle, uv, vsOut.norm_uv, s.norm_distance);

  let fw = fwidth(uv);
  let sdf_texture_grid = min(fract(uv) / fw, (1.0 - fract(uv)) / fw);
  let on_sdf_texture_grid = min(sdf_texture_grid.x, sdf_texture_grid.y) < 0.5;

  // if (on_sdf_texture_grid) {
  //   return vec4f(0.0, 1.0, 0.0, 1.0);
  // }

  let final_result = vec4f(color.rgb, color.a * alpha);

  if (base_u.debug_type > 0u) {

    // === DEBUG: per-screen-pixel-cell digit overlay ===========================
    // Cells are nominally 32×32 SCREEN pixels at 1x DPR; we multiply by
    // `base_u.debug_scale` (typically devicePixelRatio) so cells stay
    // the same physical size on retina displays. The digit pixel scale and
    // grid line width receive the same multiplier so their visual weight
    // matches across DPRs. The screen-cell centre and the matching uv-at-
    // centre are computed together; sdf.t sampled at uv-at-centre is
    // therefore uniform across all fragments inside the same screen cell,
    // so every fragment in the cell renders the same digit pair.
    let dbg_scale  = base_u.debug_scale;
    let cell       = vec2f(32.0, 32.0) * dbg_scale;
    let cell_data  = debug_screen_cell(vsOut.position.xy, vsOut.uv, cell);
    let debug_sdf  = getSample(cell_data.uv);

    // Per-cell flat-shaded background = colour of the dominant neighbour
    // (0..3). Adjacent cells with different dominants change colour at the
    // texel-grid Voronoi boundary — that's the stairstep we're hunting.

    // let cell_bg = debug_idx_to_color(select(0.0, 1.0, debug_sdf.t >= 5.0));
    // let cell_bg = select(vec4f(0.85, 0.20, 0.20, 1.0),   // outside → red
    //                     vec4f(0.20, 0.85, 0.20, 1.0),   // inside  → green
    //                     debug_sdf.is_inside < 0.0);
    let cell_bg = debug_idx_to_color(floor(debug_sdf.t));

    // Digits show the dominant neighbour's curve index (floor of its global_t).
    // If two adjacent cells have different curve indices that lines up with
    // the cell_bg colour change, we've confirmed the artifact == "neighbour-
    // pointing-at-different-curve" Voronoi pattern.

    let cell_uv = cell_data.uv;
    let debug_output = select(
      debug_render_digits(
        vsOut.position.xy,
        cell.x,
        debug_sdf.debug_probe,
        2,
        DEBUG_PIXEL_SCALE * dbg_scale
      ),
      debug_render_arrow(
        vsOut.position.xy,
        cell.x,
        debug_sdf.debug_probe,
        DEBUG_PIXEL_SCALE * dbg_scale
      ),
      base_u.debug_type == 1u
    );

    let grid = debug_grid_line(vsOut.position.xy, cell, 1.0 * dbg_scale);

    // Background → grid lines → digits, painted in that order.
    // var dbg = final_result;              // 
    var dbg = mix(final_result, cell_bg, 0.1);              // 
    dbg     = mix(dbg, vec4f(0.8), grid);     // dark grid lines
    dbg     = mix(dbg, vec4f(0.0, 1.0, 0.0, 1.0), debug_output.a); // white digits on top
    // === /DEBUG ==============================================================
    return dbg;
  } else {
    return final_result;
  }
}

// =============================================================================
// DEBUG: TINY BITMAP DIGIT RENDERER  (self-contained, copy-pasteable)
//
// Renders an integer `value` as 2 digits inside each grid cell. The function
// has no dependencies on this shader's globals — copy this whole section
// (constants + 2 functions) into any fragment shader to use it.
//
// Caller responsibilities:
//   • Pass the absolute pixel position you want digits to be relative to
//     (e.g. `vsOut.uv` if your uv is in texel space, or fragCoord, etc).
//   • Compute `value` as a single number that is CONSTANT across all pixels
//     within one grid cell, and only varies BETWEEN cells. Typically:
//       let cell_idx = vec2i(floor(px / cell_size));
//       let value    = compute_per_cell(cell_idx);
//   • Choose a `cell_size` large enough for the digits to be readable
//     (≥ ~16 in the same units as `px` is a good starting point).
//
// Returns:
//   vec4f with rgb = (1, 1, 1) and a = 1.0 on pixels that are part of a
//   digit glyph, vec4f(0) elsewhere. Mix with the underlying colour:
//       let d = debug_render_digits(vsOut.uv, 32.0, value, 0, 1.5);     // integer
//       let d = debug_render_digits(vsOut.uv, 32.0, value, 2, 1.5);     // X.YY
//       return mix(base_color, vec4f(1, 1, 0, 1), d.a);                 // yellow digits
//
// `decimal_places` controls how many fraction digits to render after a
// decimal point. 0 = integer-only (no decimal point shown). When > 0 the
// total slot count grows accordingly, so you may need a wider `cell_size`.
//
// `pixel_scale` is the screen pixels per font pixel (1.0 = thinnest 1px
// strokes, bump up for bolder glyphs). Pass `DEBUG_PIXEL_SCALE * dpr` if
// you need physical-size consistency across retina screens.
//
// Renders the value with a sign prefix for negatives, no leading zeros for
// values with non-zero integer part (so 5.5 prints as "5.5", not "05.5"; 0.5
// keeps its single leading zero). Width adapts per value, so cells with very
// different magnitudes will have different-sized digit blocks centred in
// their cells. If a block overflows its cell, increase `cell_size`.
// =============================================================================

// Snap a pixel position to the CENTRE of the grid cell it falls in. All
// fragments inside the same cell receive the same return value, so any
// downstream computation derived from it (texture sample, distance search,
// arithmetic on the position, etc.) is automatically uniform per cell.
// Pair this with `debug_render_digits` to visualise per-cell quantities:
//
//   let cell    = vec2f(32.0, 32.0);                   // 32×32 cells
//   let centre  = debug_cell_centre(vsOut.uv, cell);    // same for whole cell
//   let value   = some_function(centre);                // ⇒ same for whole cell
//   let digits  = debug_render_digits(vsOut.uv, cell.x, value, 0, DEBUG_PIXEL_SCALE);
//   return mix(base_color, vec4f(1, 1, 0, 1), digits.a);
fn debug_cell_centre(px: vec2f, cell_size: vec2f) -> vec2f {
  return (floor(px / cell_size) + vec2f(0.5)) * cell_size;
}

// All-in-one helper for the common case "I want screen-pixel cells, but I
// need to sample data living in a different coordinate space (e.g. texel uv)".
// Given the fragment's screen position and uv, returns the centre of the
// screen-pixel cell *and* the matching uv at that screen centre. Both values
// are uniform across all fragments in the same screen cell, so any data you
// derive from `result.uv` is automatically cell-uniform.
//
// Mechanics: we know how uv changes per screen pixel via dpdx/dpdy (these
// are constant within a single triangle's projection), so walking from the
// fragment to the cell centre in screen space corresponds to a known uv
// offset. Must be called from a fragment shader (dpdx/dpdy are fragment-only).
//
// Usage:
//   let cell      = vec2f(32.0, 32.0);   // 32 screen pixels per cell
//   let result    = debug_screen_cell(vsOut.position.xy, vsOut.uv, cell);
//   let sdf       = getSample(result.uv);
//   let digits    = debug_render_digits(vsOut.position.xy, cell.x, sdf.t, 0, DEBUG_PIXEL_SCALE);
//   return mix(base_color, vec4f(1, 1, 0, 1), digits.a);
struct DebugScreenCell {
  screen_centre: vec2f,  // cell centre in screen pixels (same units as `screen_pos`)
  uv: vec2f,             // uv at the screen-cell centre (same units as input `uv`)
};
fn debug_screen_cell(screen_pos: vec2f, uv: vec2f, screen_cell_size: vec2f) -> DebugScreenCell {
  let screen_centre = (floor(screen_pos / screen_cell_size) + vec2f(0.5)) * screen_cell_size;
  let screen_offset = screen_centre - screen_pos;
  let uv_at_centre  = uv + dpdx(uv) * screen_offset.x + dpdy(uv) * screen_offset.y;
  return DebugScreenCell(screen_centre, uv_at_centre);
}

// Returns 1.0 on grid-cell borders and 0.0 in cell interiors. Caller mixes
// with their preferred grid colour:
//   let g = debug_grid_line(vsOut.position.xy, vec2f(32.0), 1.0);
//   color = mix(color, vec4f(0, 0, 0, 1), g);    // black grid lines
//
// `line_width` is the line width in screen pixels (use 1.0 for the thinnest
// crisp line). The line is placed at the LEFT and TOP edge of each cell —
// because cells abut, that's also the right edge of the previous cell, so
// adjacent cells share a single `line_width`-wide border.
//
// Pixel-aligned (no AA): assumes `px` is in screen pixels with fragCoord at
// integer+0.5, which is the default for non-MSAA-per-sample shading. With
// `line_width = 1.0` exactly one pixel column / row is lit per cell boundary.
fn debug_grid_line(px: vec2f, cell_size: vec2f, line_width: f32) -> f32 {
  let in_cell = px - floor(px / cell_size) * cell_size;
  let on_grid = in_cell.x < line_width || in_cell.y < line_width;
  return select(0.0, 1.0, on_grid);
}

// Map an integer-ish value to one of 8 distinguishable RGB colours. Useful
// for visualising "which one of N things won" — Voronoi cells, dominant
// neighbour, curve-index buckets, etc. Cycles every 8 values.
fn debug_idx_to_color(idx: f32) -> vec4f {
  let i = i32(idx) & 7;
  switch i {
    case 0:       { return vec4f(0.85, 0.20, 0.20, 1.0); }   // red
    case 1:       { return vec4f(0.20, 0.85, 0.20, 1.0); }   // green
    case 2:       { return vec4f(0.20, 0.45, 0.95, 1.0); }   // blue
    case 3:       { return vec4f(0.95, 0.85, 0.20, 1.0); }   // yellow
    case 4:       { return vec4f(0.85, 0.30, 0.85, 1.0); }   // magenta
    case 5:       { return vec4f(0.20, 0.85, 0.85, 1.0); }   // cyan
    case 6:       { return vec4f(0.95, 0.55, 0.20, 1.0); }   // orange
    case 7:       { return vec4f(0.55, 0.30, 0.85, 1.0); }   // purple
    default:      { return vec4f(0.5,  0.5,  0.5,  1.0); }
  }
}

const DEBUG_DIGIT_W:    i32 = 3;  // glyph width in font pixels
const DEBUG_DIGIT_H:    i32 = 5;  // glyph height in font pixels
const DEBUG_DIGIT_GAP:  i32 = 1;  // pixels of gap between digits
// One font pixel = this many screen pixels. 1.0 = thinnest (1px strokes), bump
// up for bolder/larger digits at the cost of more cell space.
const DEBUG_PIXEL_SCALE: f32 = 1;

// 3x5 bitmap glyphs for digits 0..9. Bit (x + 3*y) is the pixel at column x
// (0..2, left→right) and row y (0..4, top→bottom). Set = on, clear = off.
fn debug_glyph(d: i32) -> u32 {
  switch d {
    case 0:       { return 0x7B6Fu; }
    case 1:       { return 0x4924u; }
    case 2:       { return 0x73E7u; }
    case 3:       { return 0x79E7u; }
    case 4:       { return 0x49EDu; }
    case 5:       { return 0x79CFu; }
    case 6:       { return 0x7BCFu; }
    case 7:       { return 0x4927u; }
    case 8:       { return 0x7BEFu; }
    case 9:       { return 0x79EFu; }
    default:      { return 0u; }
  }
}

fn debug_render_digits(px: vec2f, cell_size: f32, value: f32, decimal_places: i32, pixel_scale: f32) -> vec4f {
  // 1. Sign + magnitude.
  let is_negative = value < 0.0;
  let abs_value   = abs(value);
  let int_part    = i32(abs_value);

  // 2. Count integer-digit slots needed (≥ 1, no leading zeros). Capped at
  //    10 iterations as a safety net; handles values up to 10^10.
  var int_slots = 1;
  var n = int_part;
  for (var i = 0; i < 10; i = i + 1) {
    n = n / 10;
    if (n == 0) { break; }
    int_slots = int_slots + 1;
  }

  // 3. Slot layout, left to right:
  //      [ "-"? ] [ int_0 ... int_{int_slots-1} ] [ "."? ] [ frac_0 ... frac_{decimal_places-1}? ]
  let has_decimal      = decimal_places > 0;
  let sign_slot_count  = select(0, 1, is_negative);
  let int_start        = sign_slot_count;
  let int_end          = int_start + int_slots;
  let decimal_slot_idx = int_end;
  let frac_start       = int_end + 1;
  let total_slots      = int_end + select(0, 1 + decimal_places, has_decimal);

  let stride         = DEBUG_DIGIT_W + DEBUG_DIGIT_GAP;
  let total_w_pixels = total_slots * stride - DEBUG_DIGIT_GAP;

  // 4. Centre the digit block in the cell at the requested pixel scale.
  // Caller supplies the scale (typically `DEBUG_PIXEL_SCALE * dpr`) so the
  // function stays self-contained — it does not read DEBUG_PIXEL_SCALE.
  //
  // The scale is snapped to an integer ≥ 1 so every font pixel maps to a
  // whole number of screen pixels. A fractional scale (e.g. 1.5) causes
  // some font columns to span 2 screen pixels and others 1 depending on
  // sub-pixel alignment, producing jagged "weird pixel" rendering. The
  // origin is also snapped to integer pixels so the block doesn't straddle
  // screen-pixel boundaries when (cell_size − block_w) is odd.
  let cell_origin = floor(px / cell_size) * cell_size;
  let in_cell     = px - cell_origin;
  let scale       = max(1.0, round(pixel_scale));
  let block       = vec2f(scale * f32(total_w_pixels), scale * f32(DEBUG_DIGIT_H));
  let origin      = floor((vec2f(cell_size) - block) * 0.5);
  let local       = in_cell - origin;

  // 5. Reject pixels outside the digit block.
  if (local.x < 0.0 || local.y < 0.0 || local.x >= block.x || local.y >= block.y) {
    return vec4f(0.0);
  }

  // 6. Convert to integer font-pixel coordinates inside the block; identify
  //    which slot, and where within that slot's 3-pixel-wide column.
  let fx        = i32(floor(local.x / scale));
  let fy        = i32(floor(local.y / scale));
  let slot_idx  = fx / stride;
  let in_slot_x = fx - slot_idx * stride;
  if (in_slot_x >= DEBUG_DIGIT_W) {
    return vec4f(0.0);  // fragment falls in the inter-slot gap
  }
  let bit_index = u32(in_slot_x) + u32(fy) * 3u;

  // 7. Pick the glyph for this slot.
  var glyph: u32 = 0u;

  if (is_negative && slot_idx == 0) {
    // Minus sign: horizontal bar across the middle row (bits 6,7,8 = 0x01C0).
    glyph = 0x01C0u;
  } else if (has_decimal && slot_idx == decimal_slot_idx) {
    // Decimal point: single dot in the centre of the bottom row (bit 13).
    glyph = 0x2000u;
  } else if (slot_idx >= int_start && slot_idx < int_end) {
    // Integer digit. slot 0 of the int section is the MSD.
    let pos_from_msd = slot_idx - int_start;
    let pos_from_lsd = (int_slots - 1) - pos_from_msd;
    var divisor = 1;
    for (var i = 0; i < pos_from_lsd; i = i + 1) {
      divisor = divisor * 10;
    }
    let d = (int_part / divisor) % 10;
    glyph = debug_glyph(d);
  } else if (has_decimal && slot_idx >= frac_start) {
    // Fraction digit. frac_pos = 1 is tenths, 2 is hundredths, ...
    let frac_pos = slot_idx - decimal_slot_idx;
    var multiplier = 1;
    for (var i = 0; i < frac_pos; i = i + 1) {
      multiplier = multiplier * 10;
    }
    let d = i32(floor(abs_value * f32(multiplier))) % 10;
    glyph = debug_glyph(d);
  }

  let on = ((glyph >> bit_index) & 1u) != 0u;
  if (on) {
    return vec4f(1.0, 1.0, 1.0, 1.0);
  }
  return vec4f(0.0);
}

// =============================================================================
// DEBUG: TINY ARROW RENDERER  (self-contained, copy-pasteable)
//
// Renders a single arrow centred in each grid cell, pointing along an angle
// expressed in radians. The angle convention is **standard math (y-up
// Cartesian)**: 0 = +x (right), π/2 = +y (up), π = -x (left), -π/2 = +y
// inverted (down). The function flips the y component internally so the
// arrow visually points the right way on a y-down screen pixel grid (which
// is what `vsOut.position.xy` is in WebGPU framebuffers); callers don't
// need to negate `angle` to compensate.
//
// Caller responsibilities:
//   • Pass the absolute pixel position (e.g. `vsOut.position.xy`) so the
//     cell grid lines up with the rest of the debug overlay.
//   • Compute `angle` per-cell-uniform if you want a uniform arrow per
//     cell. Pair with `debug_screen_cell` / `debug_cell_centre` so the
//     angle is sampled once per cell instead of varying per fragment.
//   • Choose a `cell_size` ≥ ~16 pixels so the arrow is visible.
//   • `pixel_scale` controls stroke thickness in screen pixels and is
//     snapped to integer ≥ 1 (same convention as `debug_render_digits`).
//
// Returns:
//   vec4f(1, 1, 1, 1) on pixels that are part of the arrow; vec4f(0)
//   elsewhere. Mix with the underlying colour:
//     let a = debug_render_arrow(vsOut.position.xy, 32.0, angle, 1.5);
//     return mix(base_color, vec4f(1, 0, 0, 1), a.a);   // red arrow
//
// Geometry: the arrow occupies the centre of the cell. Its full length
// along the axis is ~80% of cell_size; the head is the last ~30% of that
// length. Shaft thickness scales with `pixel_scale`. Both shaft and head
// are pixel-snapped so the arrow renders cleanly without aliasing.
// =============================================================================
fn debug_render_arrow(px: vec2f, cell_size: f32, angle: f32, pixel_scale: f32) -> vec4f {
  // 1. Locate the cell and the fragment's offset from the cell centre.
  let cell_origin = floor(px / cell_size) * cell_size;
  let cell_centre = cell_origin + vec2f(cell_size * 0.5);
  let local       = px - cell_centre;

  // 2. Stroke widths and arrow proportions in screen pixels.
  let scale            = max(1.0, round(pixel_scale));
  let arrow_half_len   = cell_size * 0.4;        // tip at +arrow_half_len, tail at -arrow_half_len
  let head_len         = cell_size * 0.18;       // length of arrow head along the axis
  let shaft_end        = arrow_half_len - head_len;
  let shaft_half_width = scale;                  // shaft thickness = 2 * scale
  let head_half_width  = scale * 3.0;            // head base half-width

  // 3. Direction vector. Caller passes a math-convention (y-up) angle, but
  //    the screen pixel grid is y-down, so flip y for the rendering basis.
  //    With this flip:
  //      angle = 0     → arrow points right  (+x screen)
  //      angle = π/2   → arrow points up     (-y screen, visually up)
  //      angle = π     → arrow points left   (-x screen)
  //      angle = -π/2  → arrow points down   (+y screen, visually down)
  let dir      = vec2f(cos(angle), -sin(angle));
  // Perpendicular to dir (90° CCW in screen space; sign doesn't affect symmetric shaft / head).
  let perp_dir = vec2f(-dir.y, dir.x);

  // 4. Project fragment offset onto arrow's axis basis.
  let along = dot(local, dir);       // distance along the arrow direction (0 at centre)
  let perp  = dot(local, perp_dir);  // perpendicular distance from the axis

  // 5. Outside the arrow's axial extent → not part of the arrow.
  if (along < -arrow_half_len || along > arrow_half_len) {
    return vec4f(0.0);
  }

  // 6. Shaft region (from tail up to the head's base): rectangle of
  //    constant half-width.
  if (along <= shaft_end) {
    if (abs(perp) <= shaft_half_width) {
      return vec4f(1.0, 1.0, 1.0, 1.0);
    }
    return vec4f(0.0);
  }

  // 7. Head region (from shaft_end to tip): triangle tapering linearly
  //    from head_half_width at shaft_end to 0 at the tip.
  let head_t = (along - shaft_end) / head_len;        // 0 at base, 1 at tip
  let head_w = head_half_width * (1.0 - head_t);
  if (abs(perp) <= head_w) {
    return vec4f(1.0, 1.0, 1.0, 1.0);
  }
  return vec4f(0.0);
}
