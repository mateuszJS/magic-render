// =============================================================================
// drawShape/base.wgsl — per-fragment SDF lookup for cubic-bezier paths.
//
// CURVE STORAGE
//   `curves` is a flat storage buffer; every 4 consecutive vec2f form one cubic
//   curve (p0, p1, p2, p3).
//   Straight-line marker: p1.x > STRAIGHT_LINE_THRESHOLD. Geometry is then the
//   segment p0→p3 and (p1, p2) are ignored.
//   "No-handle" corner: cubic with p1 == p0 (no in-handle on start) and/or
//   p2 == p3 (no out-handle on end). The cubic derivative vanishes at that
//   endpoint, so we fall back to the chord direction in tangent computations.
//
// "G" ENCODING
//   Each texel stores a single float `raw`; runtime decode is g = abs(raw) - 1.
//     • floor(g) = curve index
//     • fract(g) = local bezier t in [0, 1)
//   The renderShapeSdf baker snaps t ≥ 1 to t = 0 of the NEXT curve, so every
//   junction texel has fract(g) == 0.0 EXACTLY. The corner branch in getSample
//   relies on this — `cur_idx = u32(g) % N`, `prev_idx = (cur_idx + N - 1) % N`.
//
// SDF SIGN CONVENTION
//   Sample.distance: +1 inside, −1 outside (inward-normal dot convention).
//   Final fragment-shader `distance`: NEGATIVE inside, POSITIVE outside, in
//   pixel units. (length × −Sample.distance.) Chosen so smoothstep(start, end)
//   reads strokes naturally.
//
// ARC LENGTH STORAGE
//   `arc_lengths` is a flat storage buffer of cumulative arc lengths sampled
//   at t = 0, 1/4, 2/4, 3/4 of every curve, plus one trailing total-length
//   entry. Size = 4*N + 1.
//   "Arc length" = physical distance along the curve, NOT the bezier parameter
//   t. The two are nonlinearly related (sharp bends compress t, stretched
//   regions expand it), so blending in arc-length space matches what the eye
//   sees on the path.
//   g_to_arc()    is the forward map (g → arc length).
//   arc_to_g()    is the inverse (binary search).
// =============================================================================

const STRAIGHT_LINE_THRESHOLD = 1e10;
const EPSILON = 1e-10;
const PI = 3.141592653589793;

// Background texels store ≈ −3.4e38; their fwidth is enormous. Anything larger
// than this is treated as "background derivative" and zeroed.
const FWIDTH_VALID_LIMIT = 3.402823466e+10;

// Bilinear-blend filtering thresholds (per neighbour vs nearest texel):
//   ARC_THRESHOLD      : max arc-length difference (≈ one texel of arc) before
//                        a neighbour is dropped from the blend. Empirical.
//   ANGLE_DOT_THRESHOLD: equivalent to |angle(tan_n) − angle(nearest_tan)| < 0.7π
//                        expressed as cos(0.7π) ≈ −0.809 on UNIT tangents — a
//                        single dot product, no atan2 / no wraparound bookkeeping.
const BILINEAR_ARC_THRESHOLD = 1.5;
const BILINEAR_ANGLE_DOT_THRESHOLD = -0.809016994; // cos(0.7 * PI)

// Number of stored arc-length samples per curve (at t = 0, 1/4, 2/4, 3/4).
const ARC_SAMPLES_PER_CURVE = 4.0;

// fract(g) below this counts as "exactly at curve start" (= a junction texel).
// The baker snaps t≥1 to t=0 of the next curve, so junctions ARE exactly 0,
// but we leave a tiny slop for any downstream interpolation drift.
const T_JUNCTION_EPS = 1e-5;

struct CubicBezier {
  p0: vec2f,
  p1: vec2f,
  p2: vec2f,
  p3: vec2f,
};

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

// Centralised straight-line sentinel test. If the encoding ever changes, fix
// it here and every consumer (g_to_bezier_tangent / g_to_bezier_pos /
// refine_curve_pos / corner branch) follows.
fn is_straight_line_marker(p1: vec2f) -> bool {
  return p1.x > STRAIGHT_LINE_THRESHOLD;
}

struct Vertex {
  @location(0) position: vec4f,
};

@group(0) @binding(1) var texture: texture_2d<f32>;
@group(0) @binding(2) var<uniform> camera_projection: mat4x4f;
@group(0) @binding(3) var<storage, read> curves: array<vec2f>;
@group(0) @binding(4) var<storage, read> arc_lengths: array<f32>;
// consider switching arc_lengths to a uniform buffer if size permits

// Per-shape geometric metadata. Pre-computed CPU-side and pushed once per draw
// so the fragment shader doesn't have to re-derive any of this per pixel.
//
//   texture_size   — texture dimensions in texels (= vec2f(textureDimensions(texture))).
//   total_arc_len  — arc_lengths[length-1]. Saves one storage-buffer load.
//   num_curves     — arrayLength(&curves) / 4. Avoids the runtime length query.
//
// Layout (uniform address space, total 16 bytes, struct alignment 16):
//   off  0 : texture_size    (vec2f, align 8)
//   off  8 : total_arc_len   (f32,   align 4)
//   off 12 : num_curves      (u32,   align 4)
struct PathMetrics {
  texture_size: vec2f,
  total_arc_len: f32,
  num_curves: u32,
};
@group(0) @binding(5) var<uniform> path_metrics: PathMetrics;

struct VSOutput {
  @builtin(position) position: vec4f,
  @location(0) uv: vec2f,
  @location(1) norm_uv: vec2f,
};

@vertex fn vs(vert: Vertex) -> VSOutput {
  return VSOutput(
    camera_projection * vec4f(vert.position.xy, 0.0, 1.0),
    vert.position.zw * path_metrics.texture_size,
    vert.position.zw,
  );
}


struct Sample {
  t: f32,
  distance: f32,  // +1 inside, -1 outside
};

// One cached neighbour (a single texel near the fragment) plus all the
// per-texel quantities we'll need. Computed once in loadNeighbour() so the
// downstream nearest-pick / corner / blend stages never reload `curves[]`.
struct Neighbour {
  // TODO: do we still need that (t+1) * negative or positive. Do we depend on sign of that? Or we only calcualte side base of tangent?
  g: f32,        // texel's stored g (fract = local t, floor = curve index)
  pos: vec2f,    // bezier position at g
  tan: vec2f,    // UNIT tangent at g  (g_to_bezier_tangent always normalises)
  arc: f32,      // raw cumulative arc length at g (pre-seam-wrap)
};

fn loadNeighbour(coord: vec2u) -> Neighbour {
  let raw = textureLoad(texture, coord, 0).r;
  let g = abs(raw) - 1.0;
  return Neighbour(
    g,
    g_to_bezier_pos(g + 1.0),
    g_to_bezier_tangent(g + 1.0),
    g_to_arc(g),
  );
}

// Inverse arc-length map: arc length → g (curve_idx + local_t).
fn arc_to_g(arc: f32) -> f32 {
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
  let ci = lo / u32(ARC_SAMPLES_PER_CURVE);
  let quarter = lo % u32(ARC_SAMPLES_PER_CURVE);
  let local_t = (f32(quarter) + frac) / ARC_SAMPLES_PER_CURVE;
  return f32(ci) + local_t;
}

fn getSample(pos: vec2f) -> Sample {
  let floor_pos = floor(pos - 0.5);
  let fract_pos = pos - 0.5 - floor_pos;

  let max_coord = vec2i(path_metrics.texture_size) - vec2i(1, 1);

  let p00 = vec2u(clamp(vec2i(floor_pos),                   vec2i(0, 0), max_coord));
  let p10 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 0.0)), vec2i(0, 0), max_coord));
  let p01 = vec2u(clamp(vec2i(floor_pos + vec2f(0.0, 1.0)), vec2i(0, 0), max_coord));
  let p11 = vec2u(clamp(vec2i(floor_pos + vec2f(1.0, 1.0)), vec2i(0, 0), max_coord));

  // ---------------------------------------------------------------------------
  // Fetch the four corner texels once and cache everything we need from each.
  // Replaces what used to be 4 separate textureLoads + 4 g_to_bezier_pos +
  // 4 g_to_bezier_tangent + 4 g_to_arc scattered through the function,
  // each reloading the same `curves[]` entries.
  // ---------------------------------------------------------------------------
  let n00 = loadNeighbour(p00);
  let n10 = loadNeighbour(p10);
  let n01 = loadNeighbour(p01);
  let n11 = loadNeighbour(p11);

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
  let nearest_g   = select(select(n00.g,   n10.g,   prefer_x_lo), select(n01.g,   n11.g,   prefer_x_hi), prefer_top);
  let nearest_pos = select(select(n00.pos, n10.pos, prefer_x_lo), select(n01.pos, n11.pos, prefer_x_hi), prefer_top);
  let nearest_tan = select(select(n00.tan, n10.tan, prefer_x_lo), select(n01.tan, n11.tan, prefer_x_hi), prefer_top);
  let nearest_arc = select(select(n00.arc, n10.arc, prefer_x_lo), select(n01.arc, n11.arc, prefer_x_hi), prefer_top);

  // ---------------------------------------------------------------------------
  // Sign: tangent-based half-plane test.
  // Single-tangent default works everywhere except curve junctions; at a
  // junction we ALSO consult the previous curve's end tangent. We always run
  // the two-half-plane test when fract(g)≈0 — when the corner is near-straight
  // the two half-planes give the same answer, so this reduces to the single-
  // tangent result with no threshold-driven discontinuity.
  // ---------------------------------------------------------------------------
  let inward_normal = vec2f(-nearest_tan.y, nearest_tan.x);
  var nearest_sign = sign(dot(pos - nearest_pos, inward_normal));

  if (fract(nearest_g) < T_JUNCTION_EPS) {
    let num_curves_u = path_metrics.num_curves;
    let cur_idx = u32(nearest_g) % num_curves_u;
    let prev_idx = (cur_idx + num_curves_u - 1u) % num_curves_u;
    let pp0 = curves[prev_idx * 4u + 0u];
    let pp1 = curves[prev_idx * 4u + 1u];
    let pp2 = curves[prev_idx * 4u + 2u];
    let pp3 = curves[prev_idx * 4u + 3u];

    // End tangent of prev curve at t=1. For "no-handle" corners (pp2 == pp3)
    // 3*(pp3-pp2) collapses to zero — fall back to the chord, mirroring
    // g_to_bezier_tangent's degenerate-case handling.
    let prev_chord     = pp3 - pp0;
    let prev_deriv_t1  = 3.0 * (pp3 - pp2);
    let prev_use_chord = is_straight_line_marker(pp1)
                       || dot(prev_deriv_t1, prev_deriv_t1) < 1e-12;
    let prev_tan_raw   = select(prev_deriv_t1, prev_chord, prev_use_chord);
    let prev_tan_len   = length(prev_tan_raw);
    // If even the chord is zero (fully degenerate prev curve), reuse the
    // current tangent — the corner is treated as smooth, which is the safest
    // visual outcome and avoids inventing a bogus +x axis.
    let prev_tan_n     = select(nearest_tan, prev_tan_raw / prev_tan_len, prev_tan_len > 1e-8);

    // cross2d = cur × prev. CW winding in Y-down:
    //   > 0 → concave (inner notch) → inside if EITHER half-plane says inside (max).
    //   < 0 → convex  (outer corner) → inside only if BOTH half-planes say inside (min).
    //   ≈ 0 → near-collinear → both branches give the same answer.
    let cross_2d = nearest_tan.x * prev_tan_n.y - nearest_tan.y * prev_tan_n.x;
    let prev_normal = vec2f(-prev_tan_n.y, prev_tan_n.x);
    let sign_cur  = sign(dot(pos - nearest_pos, inward_normal));
    let sign_prev = sign(dot(pos - nearest_pos, prev_normal));
    nearest_sign = select(min(sign_cur, sign_prev),
                          max(sign_cur, sign_prev),
                          cross_2d > 0.0);
  }

  // ---------------------------------------------------------------------------
  // Filter & bilinear-blend the four neighbours' arc-length values.
  //   - Drop a neighbour whose tangent points nearly opposite to nearest's
  //     (avoids smearing across folds): cheap dot-product test on UNIT tangents.
  //   - Drop a neighbour whose arc length is too far from nearest's (avoids
  //     smearing across distant parts of the path).
  //   - Wrap each neighbour's arc length to the period closest to nearest_arc
  //     so the start/end seam blends smoothly.
  // ---------------------------------------------------------------------------
  let total_arc_len = path_metrics.total_arc_len;
  let inv_arc = select(0.0, 1.0 / total_arc_len, total_arc_len > 1e-8);

  let arc00 = n00.arc + total_arc_len * round((nearest_arc - n00.arc) * inv_arc);
  let arc10 = n10.arc + total_arc_len * round((nearest_arc - n10.arc) * inv_arc);
  let arc01 = n01.arc + total_arc_len * round((nearest_arc - n01.arc) * inv_arc);
  let arc11 = n11.arc + total_arc_len * round((nearest_arc - n11.arc) * inv_arc);

  let arc_diff_00 = abs(arc00 - nearest_arc);
  let arc_diff_10 = abs(arc10 - nearest_arc);
  let arc_diff_01 = abs(arc01 - nearest_arc);
  let arc_diff_11 = abs(arc11 - nearest_arc);

  // Tangents are unit-length, so dot == cos(angle).
  let cos00 = dot(n00.tan, nearest_tan);
  let cos10 = dot(n10.tan, nearest_tan);
  let cos01 = dot(n01.tan, nearest_tan);
  let cos11 = dot(n11.tan, nearest_tan);

  let keep00 = arc_diff_00 < BILINEAR_ARC_THRESHOLD && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep10 = arc_diff_10 < BILINEAR_ARC_THRESHOLD && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep01 = arc_diff_01 < BILINEAR_ARC_THRESHOLD && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep11 = arc_diff_11 < BILINEAR_ARC_THRESHOLD && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD;

  let w00 = select(0.0, (1.0 - fract_pos.x) * (1.0 - fract_pos.y), keep00);
  let w10 = select(0.0, fract_pos.x         * (1.0 - fract_pos.y), keep10);
  let w01 = select(0.0, (1.0 - fract_pos.x) * fract_pos.y,         keep01);
  let w11 = select(0.0, fract_pos.x         * fract_pos.y,         keep11);

  let total_w = w00 + w10 + w01 + w11;
  // Fallback to nearest when all neighbours are filtered (e.g. very sharp corner).
  let arc_blended_raw = select(nearest_arc,
                               (arc00 * w00 + arc10 * w10 + arc01 * w01 + arc11 * w11) / total_w,
                               total_w > 1e-6);
  let arc_blended = clamp(arc_blended_raw, 0.0, total_arc_len);
  let blended = arc_to_g(arc_blended);

  return Sample(blended, nearest_sign);
}

// Forward arc-length map: g → cumulative arc length along the path.
fn g_to_arc(g: f32) -> f32 {
  let ci = u32(floor(g));
  let local_t = fract(g);

  // Which quarter of the curve are we in? [0..3]
  let quarter_f = local_t * ARC_SAMPLES_PER_CURVE;
  let quarter = u32(floor(quarter_f));
  let frac = fract(quarter_f);

  let lower_idx = ci * u32(ARC_SAMPLES_PER_CURVE) + quarter;
  let upper_idx = lower_idx + 1u;

  // Buffer is sized 4*N+1 and callers pass g < N, so upper_idx ≤ 4N is in
  // bounds. The clamps below are defensive in case of an unexpected overflow
  // (e.g. a caller passing exactly N or NaN-driven indexing).
  let max_idx = arrayLength(&arc_lengths) - 1u;
  let safe_lower = min(lower_idx, max_idx);
  let safe_upper = min(upper_idx, max_idx);
  return mix(arc_lengths[safe_lower], arc_lengths[safe_upper], frac);
}

// UNIT tangent at local t encoded in g. Always returns a unit-length vector
// (or (1, 0) for fully degenerate curves where even the chord is zero).
fn g_to_bezier_tangent(g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t = fract(abs_g);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  if (is_straight_line_marker(p1)) {
    let chord = p3 - p0;
    let len_sq = dot(chord, chord);
    return select(vec2f(1.0, 0.0), chord * inverseSqrt(len_sq), len_sq > 1e-12);
  }

  let mt = 1.0 - t;
  let deriv = 3.0 * (mt * mt * (p1 - p0) + 2.0 * mt * t * (p2 - p1) + t * t * (p3 - p2));
  let deriv_len_sq = dot(deriv, deriv);

  // Degenerate cubic at this endpoint (p1==p0 at t=0 or p2==p3 at t=1):
  // derivative is zero. Fall back to the chord; if even that's zero, last-
  // resort to (1, 0) so callers always see a non-zero unit vector.
  if (deriv_len_sq < 1e-12) {
    let chord = p3 - p0;
    let chord_len_sq = dot(chord, chord);
    return select(vec2f(1.0, 0.0), chord * inverseSqrt(chord_len_sq), chord_len_sq > 1e-12);
  }
  return deriv * inverseSqrt(deriv_len_sq);
}

fn g_to_bezier_pos(g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t   = fract(abs_g);
  let curve = CubicBezier(
    curves[idx * 4 + 0],
    curves[idx * 4 + 1],
    curves[idx * 4 + 2],
    curves[idx * 4 + 3]
  );

  if (is_straight_line_marker(curve.p1)) {
    return mix(curve.p0, curve.p3, t);
  }
  return bezier_point(curve, t);
}

// Refines the nearest-curve-point estimate from bilinear t interpolation by
// doing one Newton-Raphson step minimising |bezier(t) - pos|². For straight
// lines, computes the exact projection.
fn refine_curve_pos(pos: vec2f, g: f32) -> vec2f {
  let abs_g = abs(g);
  let idx = u32(abs_g) - 1u;
  let t = fract(abs_g);
  let p0 = curves[idx * 4 + 0];
  let p1 = curves[idx * 4 + 1];
  let p2 = curves[idx * 4 + 2];
  let p3 = curves[idx * 4 + 3];

  if (is_straight_line_marker(p1)) {
    let line_vec = p3 - p0;
    let len_sq = dot(line_vec, line_vec);
    // Defensive: zero-length line ⇒ refined_t = 0, return endpoint.
    let refined_t = select(0.0,
                           clamp(dot(pos - p0, line_vec) / len_sq, 0.0, 1.0),
                           len_sq > 1e-12);
    return mix(p0, p3, refined_t);
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
  let refined_t = clamp(t - select(0.0, dot(diff, dp) / df, abs(df) > 1e-8), 0.0, 1.0);
  let refined_pos = bezier_point(curve, refined_t);

  // Only accept the refined position if it's strictly closer.
  return select(orig_pos,
                refined_pos,
                dot(refined_pos - pos, refined_pos - pos) < dot(orig_pos - pos, orig_pos - pos));
}

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let sdf = getSample(vsOut.uv);
  let g = abs(sdf.t) + 1;

  // Refine the bilinear t estimate to the true nearest point on the curve.
  let curve_pos = refine_curve_pos(vsOut.uv, g);
  // TODO: shouldn't we also return refined "g"?

  // Negative inside, positive outside, in pixel-space units (see header).
  let distance = length(curve_pos - vsOut.uv) * -sdf.distance;

  // Grid: fract(uv) is how far into the current texel we are (0..1).
  // Dividing by fwidth gives distance in screen pixels from the nearest edge.
  let fw = fwidth(vsOut.uv);
  let grid = min(fract(vsOut.uv) / fw, (1.0 - fract(vsOut.uv)) / fw);
  let on_grid = min(grid.x, grid.y) < 0.5;

  ${TEST}

  let dist_derivative = length(fwidth(vsOut.uv));
  // Background derivatives are huge (≈ 3.4e38) — clamp those to 0 so we don't
  // smear the AA band into "this whole pixel is on a boundary".
  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT);
  let alpha_smooth_factor = max(safe_dist_derivative * 0.5, EPSILON);

  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, distance);
  let outer_alpha = smoothstep(u.dist_end   - alpha_smooth_factor, u.dist_end   + alpha_smooth_factor, distance);
  let alpha = outer_alpha - inner_alpha;
  var color = getColor(vec4f(distance, sdf.t, 0, 1), vsOut.uv, vsOut.norm_uv);
  
  let angle = atan2(curve_pos.x - vsOut.uv.x, curve_pos.y - vsOut.uv.y);
  color = vec4f(0, sdf.t % 1.01, 0, 1.0);
  // color = vec4f(distance / 10.0, sdf.t % 1, angle / (2 * PI), 1.0);
  
  return vec4f(color.rgb, color.a * alpha);
}
