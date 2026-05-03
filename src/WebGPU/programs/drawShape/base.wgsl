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
const TAU = 2 * PI;

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
const BILINEAR_ANGLE_DOT_THRESHOLD = -0.059016994; // cos(0.5 * PI)
// Maybe it should not be constant? Maybe it should depend on distance to the closest point?

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

// Find the previous curve in the SAME closed sub-path as cur_idx.
//
// The curve buffer concatenates all sub-paths of a shape. Within one closed
// path, consecutive curves share an endpoint: curves[K].p0 == curves[K-1].p3.
// At a path boundary (curve K is the FIRST of a new sub-path), this equality
// breaks — that's our boundary detector.
//
// For most curves the previous-in-path is just (cur - 1 + N) % N. But for the
// FIRST curve of any sub-path, that wrap would cross into a different path. We
// detect that case and walk forward from `cur_idx` to find the LAST curve of
// the current path (whose p3 wraps cleanly back to cur_idx's p0).
//
// Cost: cheap path (one vec2 compare) for non-boundary cases; O(curves-in-path)
// for the rare first-of-path case. Only invoked at junction fragments.
fn prev_curve_in_path(cur_idx: u32, num_curves: u32) -> u32 {
  // Alternative version of this function(look for next path) lives in renderShapeSdf/shader.wgsl
  let cur_p0 = curves[cur_idx * 4u + 0u];
  let candidate_prev = (cur_idx + num_curves - 1u) % num_curves;
  let candidate_p3 = curves[candidate_prev * 4u + 3u];
  let bridge = candidate_p3 - cur_p0;
  if (dot(bridge, bridge) < 1e-6) {
    return candidate_prev;
  }

  // cur_idx is the first curve of its path. Walk forward looking for the LAST
  // curve of this path: a curve i whose p3 doesn't match the next curve's p0.
  var i = cur_idx;
  for (var k = 0u; k < num_curves; k = k + 1u) {
    let next_i  = (i + 1u) % num_curves;
    let i_p3    = curves[i * 4u + 3u];
    let next_p0 = curves[next_i * 4u + 0u];
    let gap     = i_p3 - next_p0;
    if (dot(gap, gap) > 1e-6) { return i; }
    i = next_i;
  }
  // Single-curve "path" or fully connected ring — fall back to the simple wrap.
  return candidate_prev;
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
//   debug_scale    — multiplier applied to the debug-overlay grid cell and
//                    digit pixel scale. Typically `window.devicePixelRatio` so
//                    cells / digits stay the same physical size on retina
//                    displays as on 1x screens. 1.0 = no scaling.
//
// Layout (uniform address space, total 32 bytes, struct alignment 16):
//   off  0 : texture_size    (vec2f, align 8)
//   off  8 : total_arc_len   (f32,   align 4)
//   off 12 : num_curves      (u32,   align 4)
//   off 16 : debug_scale     (f32,   align 4)
//   off 20 : 12 bytes padding to round struct size up to 32
struct PathMetrics {
  texture_size: vec2f,
  total_arc_len: f32,
  num_curves: u32,
  debug_scale: f32,
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
  blend_angle: f32,
  total_weight: f32,
  number_of_valid_neighbors: f32,
  // Index 0..3 of the neighbour with the largest bilinear weight (which one
  // "wins" the blend when most others are filtered). -1.0 means "none".
  // Used by debug visualisations to expose the Voronoi-stairstep pattern.
  dominant: f32,
  // floor(global_t) of the dominant neighbour — i.e. the curve index it
  // points to. Same caveat: debug only.
  dominant_curve_idx: f32,
};

// One cached neighbour (a single texel near the fragment) plus all the
// per-texel quantities we'll need. Computed once in loadNeighbour() so the
// downstream nearest-pick / corner / blend stages never reload `curves[]`.
struct Neighbour {
  // TODO: do we still need that (t+1) * negative or positive. Do we depend on sign of that? Or we only calcualte side base of tangent?
  global_t: f32,        // texel's stored g (fract = local t, floor = curve index)
  pos: vec2f,    // bezier position at g
  tan: vec2f,    // UNIT tangent at g  (g_to_bezier_tangent always normalises)
  arc: f32,      // raw cumulative arc length at g (pre-seam-wrap)
};

fn loadNeighbour(coord: vec2u) -> Neighbour {
  let global_t = textureLoad(texture, coord, 0).r;

  return Neighbour(
    global_t,
    global_t_to_position(global_t),
    global_t_to_tangent(global_t),
    global_t_to_arc(global_t),
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
  let nearest_g   = select(select(n00.global_t,   n10.global_t,   prefer_x_lo), select(n01.global_t,   n11.global_t,   prefer_x_hi), prefer_top);
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
    let prev_idx = prev_curve_in_path(cur_idx, num_curves_u);
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

  let angle_nearest = atan2(nearest_pos.y - pos.y,nearest_pos.x - pos.x);
  let angle_00 = atan2(n00.pos.y - pos.y,n00.pos.x - pos.x);
  let angle_01 = atan2(n01.pos.y - pos.y,n01.pos.x - pos.x);
  let angle_10 = atan2(n10.pos.y - pos.y,n10.pos.x - pos.x);
  let angle_11 = atan2(n11.pos.y - pos.y,n11.pos.x - pos.x);

  // multiplied by nearest_sign because is_angle_near has only good effects when inside the shape
  let keep00 = arc_diff_00 < BILINEAR_ARC_THRESHOLD && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep01 = arc_diff_01 < BILINEAR_ARC_THRESHOLD && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep10 = arc_diff_10 < BILINEAR_ARC_THRESHOLD && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD;
  let keep11 = arc_diff_11 < BILINEAR_ARC_THRESHOLD && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD;

  // let keep00 = select(arc_diff_00 < BILINEAR_ARC_THRESHOLD && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD, is_angle_near(angle_00, angle_nearest), -nearest_sign * d00 > 20000);
  // let keep01 = select(arc_diff_01 < BILINEAR_ARC_THRESHOLD && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD, is_angle_near(angle_01, angle_nearest), -nearest_sign * d01 > 20000);
  // let keep10 = select(arc_diff_10 < BILINEAR_ARC_THRESHOLD && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD, is_angle_near(angle_10, angle_nearest), -nearest_sign * d10 > 20000);
  // let keep11 = select(arc_diff_11 < BILINEAR_ARC_THRESHOLD && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD, is_angle_near(angle_11, angle_nearest), -nearest_sign * d11 > 20000);

  // let keep00 =  && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep10 = is_angle_near(angle_10, angle_nearest) && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep01 = is_angle_near(angle_01, angle_nearest) && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep11 = is_angle_near(angle_11, angle_nearest) && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD;

  // let keep00 = arc_diff_00 < BILINEAR_ARC_THRESHOLD && cos00 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep10 = arc_diff_10 < BILINEAR_ARC_THRESHOLD && cos10 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep01 = arc_diff_01 < BILINEAR_ARC_THRESHOLD && cos01 > BILINEAR_ANGLE_DOT_THRESHOLD;
  // let keep11 = arc_diff_11 < BILINEAR_ARC_THRESHOLD && cos11 > BILINEAR_ANGLE_DOT_THRESHOLD;

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
  let blended_global_t = arc_to_g(arc_blended);

  // ---------------------------------------------------------------------------
  // blend_angle: angle from `pos` toward the closest curve point.
  //
  //  - High-confidence regime (total_w >= 0.5). The keep-filtered blend
  //    has enough weight that refining `blended_global_t` to the true
  //    closest point on its curve gives a smooth, geometry-correct
  //    answer. We mirror the fragment shader's primary `angle`
  //    computation exactly: refine, then atan2(curve_pos - pos).
  //
  //  - Fallback regime (total_w < 0.5). The keep filter has dropped
  //    most neighbours and the refined position staircases at the
  //    texel-grid Voronoi boundaries. Bilinear-blend the four
  //    neighbours' UNIT tangents — using RAW bilinear weights, NOT
  //    gated by keepXX, so all four contribute regardless of arc /
  //    angle / pos rejection — atan2 the sum once, and rotate by ±π/2
  //    to get the perpendicular (the angle from the curve point back
  //    to `pos`). The rotation sign comes from `nearest_sign`:
  //      inward_normal = (-tan.y, tan.x)
  //      curve_pos - pos = -nearest_sign * inward_normal
  //    so angle = tangent_angle - nearest_sign * π/2. Tangents are
  //    unit-length so the bilinear sum is generally NOT unit-length,
  //    but atan2 only cares about direction, so no normalisation
  //    needed. Cost: 1 atan2 instead of 4, no Newton, no per-neighbour
  //    side test.
  // ---------------------------------------------------------------------------
  let refined_primary = refine_curve_pos(pos, blended_global_t);
  let primary_angle = atan2(refined_primary.pos.y - pos.y, refined_primary.pos.x - pos.x);

  let bw00 = (1.0 - fract_pos.x) * (1.0 - fract_pos.y);
  let bw10 = fract_pos.x         * (1.0 - fract_pos.y);
  let bw01 = (1.0 - fract_pos.x) * fract_pos.y;
  let bw11 = fract_pos.x         * fract_pos.y;
  let blend_tan_sum = n00.tan * bw00 + n10.tan * bw10 + n01.tan * bw01 + n11.tan * bw11;
  let blend_tan_angle = atan2(blend_tan_sum.y, blend_tan_sum.x);
  let fallback_angle = blend_tan_angle - nearest_sign * (PI * 0.5);

  let blend_angle = select(fallback_angle, primary_angle, total_w >= 0.5);

  let number_of_valid_neighbors = 0.0 +
    select(0.0, 1.0, keep00) +
    select(0.0, 1.0, keep01) +
    select(0.0, 1.0, keep10) +
    select(0.0, 1.0, keep11);

  // Dominant neighbour: the one with the largest bilinear weight. When the
  // filter has dropped most candidates, this single neighbour effectively
  // determines the blend, and which neighbour wins flips at texel-grid
  // boundaries (= the Voronoi stairstep we want to visualise).
  var dominant: f32 = -1.0;
  var dom_w:    f32 = 0.0;
  if (w00 > dom_w) { dominant = 0.0; dom_w = w00; }
  if (w10 > dom_w) { dominant = 1.0; dom_w = w10; }
  if (w01 > dom_w) { dominant = 2.0; dom_w = w01; }
  if (w11 > dom_w) { dominant = 3.0; dom_w = w11; }

  let dom_g = select(
    select(n00.global_t, n10.global_t, dominant > 0.5),
    select(n01.global_t, n11.global_t, dominant > 2.5),
    dominant > 1.5,
  );
  let dominant_curve_idx = floor(dom_g);

  return Sample(
    blended_global_t,
    nearest_sign,
    blend_angle,
    total_w,
    number_of_valid_neighbors,
    dominant,
    dominant_curve_idx,
  );
}

// Forward arc-length map: g → cumulative arc length along the path.
fn global_t_to_arc(global_t: f32) -> f32 {
  let curve_index = u32(global_t);
  let local_t = fract(global_t);

  // Which quarter of the curve are we in? [0..3]
  let quarter_f = local_t * ARC_SAMPLES_PER_CURVE;
  let quarter = u32(floor(quarter_f));
  let frac = fract(quarter_f);

  let lower_idx = curve_index * u32(ARC_SAMPLES_PER_CURVE) + quarter;
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
fn global_t_to_tangent(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let t = fract(global_t);
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

fn global_t_to_position(global_t: f32) -> vec2f {
  let idx = u32(global_t);
  let t   = fract(global_t);
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
fn refine_curve_pos(pos: vec2f, global_t: f32) -> Refined {
  
  let idx = u32(global_t);
  let t = fract(global_t);
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
    return Refined(
      mix(p0, p3, refined_t),
      refined_t
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
  let refined_t = clamp(t - select(0.0, dot(diff, dp) / df, abs(df) > 1e-8), 0.0, 1.0);
  let refined_pos = bezier_point(curve, refined_t);

  // Only accept the refined position if it's strictly closer.
  let condition = dot(refined_pos - pos, refined_pos - pos) < dot(orig_pos - pos, orig_pos - pos);
  let best_pos = select(orig_pos, refined_pos, condition);
  let best_t = select(global_t, refined_t, condition);

  return Refined(best_pos, best_t);
}

struct Refined {
  pos: vec2f,
  t: f32
};

@fragment fn fs(vsOut: VSOutput) -> @location(0) vec4f {
  let uv = vsOut.uv;
  let sdf        = getSample(uv);


  // Refine the bilinear t estimate to the true nearest point on the curve.
  let refined = refine_curve_pos(uv, sdf.t);
  let curve_pos = refined.pos;
  let g = refined.t;

  // Negative inside, positive outside, in pixel-space units (see header).
  let distance = length(curve_pos - uv) * -sdf.distance;
  let angle = atan2(curve_pos.y - uv.y, curve_pos.x - uv.x);

  // Grid: fract(uv) is how far into the current texel we are (0..1).
  // Dividing by fwidth gives distance in screen pixels from the nearest edge.
  let fw = fwidth(uv);
  let texel_grid = min(fract(uv) / fw, (1.0 - fract(uv)) / fw);
  let on_texel_grid = min(texel_grid.x, texel_grid.y) < 0.5;


  ${TEST}

  let dist_derivative = length(fwidth(uv));
  // Background derivatives are huge (≈ 3.4e38) — clamp those to 0 so we don't
  // smear the AA band into "this whole pixel is on a boundary".
  let safe_dist_derivative = select(0.0, dist_derivative, dist_derivative <= FWIDTH_VALID_LIMIT);
  let alpha_smooth_factor = max(safe_dist_derivative * 0.5, EPSILON);

  let inner_alpha = smoothstep(u.dist_start - alpha_smooth_factor, u.dist_start + alpha_smooth_factor, distance);
  let outer_alpha = smoothstep(u.dist_end   - alpha_smooth_factor, u.dist_end   + alpha_smooth_factor, distance);
  let alpha = outer_alpha - inner_alpha;
  var color = getColor(distance, g, sdf.blend_angle, uv, vsOut.norm_uv);
  
  // color = vec4f(distance, sdf.t % 100, 0, 1.0);
  // color = vec4f(distance / 10.0, sdf.t % 1, angle / (2 * PI), 1.0);


  // if (on_grid) {
  //   return vec4f(0, 1, 0, 1);
  // }

  // let norm_angle = ((angle + TAU) % TAU) / TAU;

  // if (distance >= 0) {
  //   return vec4f(norm_angle, 0, 0, 1);
  // }
  // discard;

  let final_result = vec4f(color.rgb, color.a * alpha);

    // === DEBUG: per-screen-pixel-cell digit overlay ===========================
    // Cells are nominally 32×32 SCREEN pixels at 1x DPR; we multiply by
    // `path_metrics.debug_scale` (typically devicePixelRatio) so cells stay
    // the same physical size on retina displays. The digit pixel scale and
    // grid line width receive the same multiplier so their visual weight
    // matches across DPRs. The screen-cell centre and the matching uv-at-
    // centre are computed together; sdf.t sampled at uv-at-centre is
    // therefore uniform across all fragments inside the same screen cell,
    // so every fragment in the cell renders the same digit pair.
    let dbg_scale  = path_metrics.debug_scale;
    let cell       = vec2f(32.0, 32.0) * dbg_scale;
    let cell_data  = debug_screen_cell(vsOut.position.xy, vsOut.uv, cell);
    let debug_sdf  = getSample(cell_data.uv);

    // Per-cell flat-shaded background = colour of the dominant neighbour
    // (0..3). Adjacent cells with different dominants change colour at the
    // texel-grid Voronoi boundary — that's the stairstep we're hunting.

    // let cell_bg    = debug_idx_to_color(debug_sdf.dominant);

    // Digits show the dominant neighbour's curve index (floor of its global_t).
    // If two adjacent cells have different curve indices that lines up with
    // the cell_bg colour change, we've confirmed the artifact == "neighbour-
    // pointing-at-different-curve" Voronoi pattern.
    let digits     = debug_render_digits(vsOut.position.xy, cell.x, debug_sdf.blend_angle, 2, DEBUG_PIXEL_SCALE * dbg_scale);
    let grid       = debug_grid_line(vsOut.position.xy, cell, 1.0 * dbg_scale);

    // Background → grid lines → digits, painted in that order.
    // var dbg = mix(final_result, cell_bg, 0.6);              // tint by dominant
    var dbg     = mix(final_result, vec4f(0.1, 0.1, 0.1, 1.0), grid);     // dark grid lines
    dbg     = mix(dbg, vec4f(1.0, 1.0, 1.0, 1.0), digits.a); // white digits on top
    // === /DEBUG ==============================================================
    return dbg;
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
const DEBUG_PIXEL_SCALE: f32 = 1.5;

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
