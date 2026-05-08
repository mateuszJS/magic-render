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
// ARC LENGTH STORAGE
//   `arc_lengths` is a flat storage buffer of cumulative arc lengths sampled
//   at t = 0, 1/4, 2/4, 3/4 of every curve, plus one trailing total-length
//   entry. Size = 4*N + 1.
//   "Arc length" = physical distance along the curve, NOT the bezier parameter
//   t. The two are nonlinearly related (sharp bends compress t, stretched
//   regions expand it), so blending in arc-length space matches what the eye
//   sees on the path.
//   g_to_arc()    is the forward map (g → arc length).
//   arc_to_t()    is the inverse (binary search).
// 
// 
//   Every T is global, if we deal with local t then the name is "local_t"
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

// Step along the path (in ARC-LENGTH units, i.e. world distance walked along
// the curve) for the arc-sampled `soft_nearest_angle` blender. The function
// samples the curve at (arc − step, arc, arc + step) and tent-blends the
// three direction-to-fragment unit vectors with weights 0.25 / 0.5 / 0.25.
//
//   Smaller step → sharper medial axis.
//   Larger step  → softer; eventually the three samples cover most of the
//                  path and the angle becomes meaningless.
//
// Arc length (not bezier `t`) because t is non-linear: sharp bends compress
// it, stretched regions expand it. Equal arc steps give equal world-space
// walks along the curve, regardless of texel resolution or local curvature.
const SOFT_NEAREST_ARC_STEP: f32 = 2.0;

// Global-arc soft-min blender (`global_arc_soft_min_angle`) parameters.
//
// Sweep the entire path at GLOBAL_ARC_SAMPLES evenly-spaced arc positions,
// soft-min-blend the unit directions toward each sampled curve point.
//
//   GLOBAL_ARC_SAMPLES — sampling density along the path. Higher = finer
//                        medial-axis resolution (catches sharper concave
//                        features), at proportional compute cost. The cost
//                        is independent of texel resolution, only of N.
//
//   GLOBAL_ARC_TAU_FACTOR — softening width as a fraction of d_min (the
//                           closest sampled distance). The medial axis
//                           softens over roughly TAU_FACTOR × d_min in
//                           world units. 0.0 = hard min, 1.0 = aggressive
//                           uniform blend.
const GLOBAL_ARC_SAMPLES:    i32 = 64;
const GLOBAL_ARC_TAU_FACTOR: f32 = 0.3;

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
fn prev_curve_in_path(cur_idx: u32) -> u32 {
  // Alternative version of this function(look for next path) lives in renderShapeSdf/shader.wgsl
  let cur_p0 = curves[cur_idx * 4u + 0u];
  let candidate_prev = (cur_idx + base_u.num_curves - 1u) % base_u.num_curves;
  let candidate_p3 = curves[candidate_prev * 4u + 3u];
  let bridge = candidate_p3 - cur_p0;
  if (dot(bridge, bridge) < 1e-6) {
    return candidate_prev;
  }

  // cur_idx is the first curve of its path. Walk forward looking for the LAST
  // curve of this path: a curve i whose p3 doesn't match the next curve's p0.
  var i = cur_idx;
  for (var k = 0u; k < base_u.num_curves; k = k + 1u) {
    let next_i  = (i + 1u) % base_u.num_curves;
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
struct BaseUniform {
  texture_size: vec2f,
  total_arc_len: f32,
  num_curves: u32,
  debug_scale: f32,
  debug_arrow: u32,
};
@group(0) @binding(5) var<uniform> base_u: BaseUniform;

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


struct Sample {
  t: f32,
  is_inside: f32,  // +1 inside, -1 outside
  blend_angle: f32,
  total_weight: f32,
  number_of_valid_neighbors: f32,
  // Index 0..3 of the neighbour with the largest bilinear weight (which one
  // "wins" the blend when most others are filtered). -1.0 means "none".
  // Used by debug visualisations to expose the Voronoi-stairstep pattern.
  dominant: f32,
  // floor(t) of the dominant neighbour — i.e. the curve index it
  // points to. Same caveat: debug only.
  dominant_curve_idx: f32,
  abs_distance: f32,
  debug_probe: f32,
};

// One cached neighbour (a single texel near the fragment) plus all the
// per-texel quantities we'll need. Computed once in loadNeighbour() so the
// downstream nearest-pick / corner / blend stages never reload `curves[]`.
struct Neighbour {
  // TODO: do we still need that (t+1) * negative or positive. Do we depend on sign of that? Or we only calcualte side base of tangent?
  t: f32,        // texel's stored g (fract = local t, floor = curve index)
  pos: vec2f,    // bezier position at g
  tan: vec2f,    // UNIT tangent at g  (g_to_bezier_tangent always normalises)
  arc: f32,      // raw cumulative arc length at g (pre-seam-wrap)
  norm_raw_dir: vec2f,
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

  // blended angle better performs with uniformy spreaded gradient
  // like raw values, more then refined precise value whcih tends to branch towards particular angles
  // closer to the medial axis
  let raw_pos = t_to_pos(raw_t);
  let norm_raw_dir = normalize(raw_pos - pos);

  let debug_probe = 0.0;

  return Neighbour(
    redefined_t,
    t_to_pos(redefined_t),
    t_to_tan(redefined_t),
    t_to_arc(redefined_t),
    norm_raw_dir,
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
  let ci = lo / u32(ARC_SAMPLES_PER_CURVE);
  let quarter = lo % u32(ARC_SAMPLES_PER_CURVE);
  let local_t = (f32(quarter) + frac) / ARC_SAMPLES_PER_CURVE;
  // return f32(ci) + local_t;
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
  let norm_raw_dir = vec2f(99999999); // Seems like not used?
  let nearest_debug_probe = select(select(n00.debug_probe, n10.debug_probe, prefer_x_lo), select(n01.debug_probe, n11.debug_probe, prefer_x_hi), prefer_top);

  return Neighbour(
    nearest_g,
    nearest_pos,
    nearest_tan,
    nearest_arc,
    norm_raw_dir,
    nearest_debug_probe,
  );
}

// Resolution-independent soft-nearest angle by sampling the curve at three
// points evenly spaced in ARC LENGTH around the bilinear-blended `arc` value:
// (arc − step, arc, arc + step). For each sample we take the unit direction
// from `pos` toward the curve point at that arc, then tent-blend the three
// directions with weights 0.25 / 0.5 / 0.25 and atan2 the result.
//
// Why arc, not t:
//   Bezier `t` is non-linear in distance — sharp bends compress it, slow
//   regions expand it. A fixed step in `t` would walk a wildly varying
//   physical distance along the curve. Arc length is linear in world
//   distance, so a fixed step gives a uniform sample stride along the
//   path, which is what we want for a symmetric tent kernel.
//
// Why this softens the medial axis:
//   Near the skeleton, the closest curve point as a function of fragment
//   position changes RAPIDLY in arc — a small fragment shift past the
//   skeleton flips the "best" arc from one side of the path to the other.
//   The three-arc tent blends directions across that flip, so the angle
//   rotates smoothly through the skeleton instead of snapping.
//
// Why this is resolution-independent:
//   Nothing here depends on texel size; `arc` and `step` are world-units
//   quantities and we only read the curve / arc-length buffers.

struct SoftAngleDebug {
  angle: f32,
  debug_probe: f32,
}

fn soft_nearest_angle(pos: vec2f, arc: f32) -> SoftAngleDebug {
  let total = base_u.total_arc_len;
  // Clamp to the open path's arc range. Closed paths could wrap with
  // modulo, but that's wrong across multi-subpath shapes (e.g. letter
  // counters), so we play safe.

  let tan_minus_2 = t_to_tan(arc_to_t(arc - 2));
  let tan_minus_1 = t_to_tan(arc_to_t(arc - 1));
  let tan_curr  = t_to_tan(arc_to_t(arc));
  let tan_plus_1  = t_to_tan(arc_to_t(arc + 1));
  let tan_plus_2  = t_to_tan(arc_to_t(arc + 2));

  let interpolate_towards = sign(
    dot(tan_plus_1, tan_plus_2) - dot(tan_minus_1, tan_minus_2)
  );

  var inter_far: vec2f;
  var inter: vec2f;

  if (interpolate_towards < 0.0) {
    // go towards plus
    inter_far = tan_plus_2;
    inter = tan_plus_1;
  } else {
    // go towards minus
    inter_far = tan_minus_2;
    inter = tan_minus_1;
  }

  // Tent blend in vector space; atan2 once. Vector-space averaging handles
  // angle wraparound naturally — no modulo bookkeeping needed.
  let blended = 0.45 * inter_far + 0.35 * inter + 0.2 * tan_curr;
  let outward = vec2f(-blended.y, blended.x); // 90 degree CCW, points outward from the curve
  return SoftAngleDebug(atan2(outward.y, outward.x), atan2(outward.y, outward.x));
}

// Resolution-independent angle field by sweeping the ENTIRE path at
// GLOBAL_ARC_SAMPLES evenly-arc-spaced positions and soft-min-blending the
// unit directions from `pos` toward each sampled curve point.
//
// Why this dodges every previous failure mode:
//   - Resolution-independent: nothing references the texel grid, only the
//     curve & arc-length buffers. Increasing texture density doesn't
//     change the result at all.
//   - Catches every medial axis: with a global sweep, the equidistant
//     "second branch" at the skeleton is always among the samples, no
//     matter how far it is in arc from the primary closest point. The
//     4-bilinear-neighbour formulations couldn't see it when the texels
//     themselves didn't span both sides; here the curve buffer does.
//   - Smooth softening: soft-min in world units. τ = TAU_FACTOR × d_min
//     so softening width scales with how far we are from the boundary
//     (wider blend deep in the interior, sharper near the curve).
//
// `d_min` is the caller's already-computed Newton-refined distance from
// `pos` to the nearest curve point. Used both as the soft-min reference
// (weights = exp(-(d_i - d_min)/τ)) and to scale τ. Passing it in lets us
// skip a pre-pass through the samples that would otherwise compute it.
fn global_arc_soft_min_angle(pos: vec2f, d_min: f32) -> f32 {
  let total = base_u.total_arc_len;
  let n_f = f32(GLOBAL_ARC_SAMPLES);

  // τ in world units, scaled by d_min so softening adapts to interior depth.
  let tau = max(GLOBAL_ARC_TAU_FACTOR * d_min, 1e-6);
  let inv_tau = 1.0 / tau;

  // Single weighted pass. Samples sit at arc = (i + 0.5) * total / N — the
  // half-open offset avoids double-sampling arc=0 and arc=total in closed
  // paths. exp(-(d - d_min)/τ) peaks at the closest sample (≈1 since d_min
  // is the true closest by construction) and decays for far samples.
  var sum = vec2f(0.0);
  for (var i = 0; i < GLOBAL_ARC_SAMPLES; i = i + 1) {
    let arc = (f32(i) + 0.5) * total / n_f;
    let p = t_to_pos(arc_to_t(arc));
    let to_curve = p - pos;
    let d = length(to_curve);
    if (d < 1e-6) { continue; }
    let w = exp(-(d - d_min) * inv_tau);
    sum = sum + (to_curve / d) * w;
  }
  return atan2(sum.y, sum.x);
}

struct DebugValue {
  value: f32,
  debug_probe: f32,
}
fn my_custom_angle_solution(pos: vec2f, arc_primary: f32, d_min: f32) -> DebugValue {
  let arc_offset = 0.2 * (0.36 * d_min * d_min + 1.05 * d_min - 1.19);
  let arc_curr = t_to_tan(arc_to_t(arc_primary));
  let arc_forward = t_to_tan(arc_to_t(arc_primary + arc_offset));
  let arc_backward = t_to_tan(arc_to_t(arc_primary - arc_offset));
  let forward_dot = dot(arc_forward, arc_curr);
  let backward_dot = dot(arc_backward, arc_curr);

  // return DebugValue(0.0, atan2(arc_forward.y, arc_forward.x));

  if (forward_dot < backward_dot) {
    let outward_tan = vec2f(-arc_forward.y, arc_forward.x);
    let outward_angle = atan2(outward_tan.y, outward_tan.x);
    return DebugValue(outward_angle, outward_angle);
  }

    let outward_tan = vec2f(-arc_backward.y, arc_backward.x);
    let outward_angle = atan2(outward_tan.y, outward_tan.x);
    return DebugValue(outward_angle, outward_angle);

}


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

  let inward_normal = vec2f(nNearest.tan.y, -nNearest.tan.x); // 90 degree CCW,
  // inward -> something moving towards from the center(shape), towards the interior

  // nNearest.pos - pos points towards curve, so different direction base if inside or outside.
  // Dot will return 1 if direction is towards the inside. This is true onyl for exterior pixels, all pixels insdie shape
  // will point toward closest curve, so exterior, that's why we multiply by -1
  var is_inside = -sign(dot(nNearest.pos - pos, inward_normal));
  
  if (fract(nNearest.t) < T_JUNCTION_EPS) {
    // when corner is sharp(or jsut tangent discontinue), then for many pixels the closest point will be local_t = 0, singular point
    // of the current path, but it causes issues when actually the previous path should be used
    // see ./artifacts/cave incorrect path.png and ./artifacts/exterior incorrect path.png

    let cur_idx = u32(nNearest.t) % base_u.num_curves;
    let prev_idx = prev_curve_in_path(cur_idx);
    let prev_max_t = f32(prev_idx) + 1 - T_JUNCTION_EPS;
    let prev_tan = t_to_tan(prev_max_t);
    
    let cross_2d = nNearest.tan.x * prev_tan.y - prev_tan.x * nNearest.tan.y;
    // cross2d = curr x prev. CW winding in Y-down:
    //   > 0 → conves, like exterior pixels around the rect corner(outside the shape)
    //   < 0 → concave, like interior pixels around the rect corner(inside the shape)
    //   ≈ 0 → near-collinear → both branches give the same answer.
    // WARNING: it only works because of CW paths + Y-up coordinates.

    let sign_cur  = sign(dot(pos - nNearest.pos, inward_normal));
    // for exterior pixels, pos - nNearest.pos points toward exterior

    let prev_normal = vec2f(prev_tan.y, -prev_tan.x);
    let sign_prev = sign(dot(pos - nNearest.pos, prev_normal));
  
    is_inside = select(min(sign_cur, sign_prev),
                          max(sign_cur, sign_prev),
                          cross_2d < 0.0);
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
  let total_arc_len = base_u.total_arc_len;
  let inv_arc = select(0.0, 1.0 / total_arc_len, total_arc_len > 1e-8);

  let arc00 = n00.arc + total_arc_len * round((nNearest.arc - n00.arc) * inv_arc);
  let arc10 = n10.arc + total_arc_len * round((nNearest.arc - n10.arc) * inv_arc);
  let arc01 = n01.arc + total_arc_len * round((nNearest.arc - n01.arc) * inv_arc);
  let arc11 = n11.arc + total_arc_len * round((nNearest.arc - n11.arc) * inv_arc);

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
  let arc_blended_raw = select(nNearest.arc,
                               (arc00 * w00 + arc10 * w10 + arc01 * w01 + arc11 * w11) / total_w,
                               total_w > 1e-6);
  let arc_blended = clamp(arc_blended_raw, 0.0, total_arc_len);
  let _blended_global_t = arc_to_t(arc_blended);

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

  // Doing more than Newton-Raphson does not provide any better results for "T" or random wavy/fluid shapes
  // let blended_global_t = _blended_global_t;
  // let refined_primary = Refined(global_t_to_position(blended_global_t), _blended_global_t);

  let refined_primary = refine_curve_pos(pos, _blended_global_t);
  let blended_global_t = refined_primary.t;

  let primary_angle = atan2(refined_primary.pos.y - pos.y, refined_primary.pos.x - pos.x);

    let refined_blended_global_t = refine_curve_pos(pos, blended_global_t).t; // looks good for distance
  let abs_distance = length(pos - t_to_pos(refined_blended_global_t));
  debug_probe = abs_distance;

  // Resolution-independent arc-sampled blend. Three samples on the curve at
  // (arc − step, arc, arc + step), tent-weighted 0.25/0.5/0.25. Tune step
  // via SOFT_NEAREST_ARC_STEP at the top of this file. No texture reads —
  // only curve/arc-length buffer evaluations.
  // let result_soft_angle = soft_nearest_angle(pos, arc_blended);
  // let fallback_angle = result_soft_angle.angle;

  // Global-arc soft-min sweep. Samples GLOBAL_ARC_SAMPLES positions along the
  // entire path and soft-min-blends the unit directions toward each sampled
  // curve point. Tune GLOBAL_ARC_SAMPLES / GLOBAL_ARC_TAU_FACTOR at the top
  // of this file. No texture reads — independent of texel resolution.
  let fallback_angle = global_arc_soft_min_angle(pos, abs_distance);
  


  // If we refine neighbours then we HAVE TO do this additiona refinement here, otherwise
  // we got noise (see ./artifacts/neighbour refinement only noise.png)

  // debug_probe = result_soft_angle.debug_probe;
  // Blending angles on curve looks ugly because they mix texels inside with texels outside, 
  // those two groups point to the opposite angles (see ./artifacts/blend angles on curve.png)
  // so we add condition with distance
  let blend_angle = fallback_angle;
  // let blend_angle = select(fallback_angle, primary_angle, abs_distance < 1);

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
    select(n00.t, n10.t, dominant > 0.5),
    select(n01.t, n11.t, dominant > 2.5),
    dominant > 1.5,
  );
  let dominant_curve_idx = floor(dom_g);

  

  return Sample(
    refined_blended_global_t,
    is_inside, // -1 = outside, 1 = inside
    blend_angle,
    total_w,
    number_of_valid_neighbors,
    dominant,
    dominant_curve_idx,
    abs_distance,
    debug_probe,
  );
}

// Forward arc-length map: g → cumulative arc length along the path.
fn t_to_arc(global_t: f32) -> f32 {
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

// returns unit vector tangent at global t
fn t_to_tan(global_t: f32) -> vec2f {
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

  if (deriv_len_sq >= 1e-12) {
    return deriv * inverseSqrt(deriv_len_sq);
  }

  // First derivative vanished. Use the second derivative — that's what the
  // curve actually does next. For a cubic:
  //   B''(t) = 6 * ((1-t)*(P2 - 2*P1 + P0) + t*(P3 - 2*P2 + P1))
  //   B''(0) = 6 * (P2 - 2*P1 + P0)
  //   B''(1) = 6 * (P3 - 2*P2 + P1)
  // The leading constant 6 is irrelevant for normalisation.
  let dd = mt * (p2 - 2.0 * p1 + p0) + t * (p3 - 2.0 * p2 + p1);
  let dd_len_sq = dot(dd, dd);

  if (dd_len_sq >= 1e-12) {
    // At t=1 endpoint with P2 == P3, B'' points from P3 back toward P1, so
    // the "direction of motion approaching t=1" is the negative. Flip sign
    // when we're at the t=1 endpoint specifically — for interior t, both
    // B' and B'' point along the curve direction as t increases.
    let sign = select(1.0, -1.0, t > 0.5 && deriv_len_sq < 1e-12);
    return dd * sign * inverseSqrt(dd_len_sq);
  }

  // Both B' and B'' vanished (e.g. P0 == P1 == P2). Cubic's third
  // derivative is constant: B'''(t) = 6 * (P3 - 3*P2 + 3*P1 - P0). Use that.
  let ddd = p3 - 3.0 * p2 + 3.0 * p1 - p0;
  let ddd_len_sq = dot(ddd, ddd);
  return select(vec2f(1.0, 0.0), ddd * inverseSqrt(ddd_len_sq), ddd_len_sq > 1e-12);
}

fn t_to_pos(global_t: f32) -> vec2f {
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
  let sdf        = getSample(uv);

  // Refine the bilinear t estimate to the true nearest point on the curve.
  // let refined = refine_curve_pos(uv, sdf.t);
  // let curve_pos = refined.pos;
  // let g = refined.t;
  let curve_pos = t_to_pos(sdf.t);
  let g = sdf.t;

  // let curve_pos = global_t_to_position(sdf.t);
  // let g = sdf.t;

  // Negative inside, positive outside, in pixel-space units (see header).
  let distance = length(curve_pos - uv) * sdf.is_inside;
  let angle = atan2(curve_pos.y - uv.y, curve_pos.x - uv.x);

  // Grid: fract(uv) is how far into the current texel we are (0..1).
  // Dividing by fwidth gives distance in screen pixels from the nearest edge.


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

  // let idx = u32(g);
  // let t = fract(g);
  // let p0 = curves[idx * 4 + 0];
  // let p3 = curves[idx * 4 + 3];

  // if (length(uv - p0) < 0.1 || length(uv - p3) < 0.1) {
  //   color = vec4f(0, 1, 0, 1);
  // } 
  // else if (abs(distance) < 0.05) {
  //   color = vec4f(0, 0, 1, 1);
  // }
  
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

  let fw = fwidth(uv);
  let sdf_texture_grid = min(fract(uv) / fw, (1.0 - fract(uv)) / fw);
  let on_sdf_texture_grid = min(sdf_texture_grid.x, sdf_texture_grid.y) < 0.5;

  // if (on_sdf_texture_grid) {
  //   return vec4f(0.0, 1.0, 0.0, 1.0);
  // }

  let final_result = vec4f(color.rgb, color.a * alpha);

    if (base_u.debug_arrow > 0u) {

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

      let debug_curve_pos = t_to_pos(debug_sdf.t);
      let probe = length(debug_curve_pos - cell_data.uv) * debug_sdf.is_inside;

      let cell_uv = cell_data.uv;
      
      var debug_output: vec4f;
      if (base_u.debug_arrow == 1u) {
        debug_output = debug_render_arrow(
          vsOut.position.xy,
          cell.x,
          debug_sdf.debug_probe, // debug_sdf.is_inside,
          DEBUG_PIXEL_SCALE * dbg_scale
        );
      } else {
        debug_output = debug_render_digits(
          vsOut.position.xy,
          cell.x,
          debug_sdf.debug_probe, // debug_sdf.is_inside,
          2,
          DEBUG_PIXEL_SCALE * dbg_scale
        );
      }


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
