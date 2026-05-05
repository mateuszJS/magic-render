const types = @import("types.zig");
const sdf_drawing = @import("sdf/drawing.zig");
const consts = @import("consts.zig");
const webgpu_glue = @import("webgpu_glue.zig");
const std = @import("std");
const utils = @import("utils.zig");
const shared = @import("shared.zig");
const assets = @import("assets.zig");
const js_glue = @import("js_glue.zig");
const path_utils = @import("shapes/path_utils.zig");

pub fn computeShape(
    tex_id: u32,
    bounds: [4]types.PointUV,
    padding: f32,
    paths: [][]types.Point, // it has to be a safe copy allocated with on a heap, all paths are closed
    resize: f32,
) !sdf_drawing.SdfTex {
    var sdf_tex = sdf_drawing.getTexture(
        tex_id,
        bounds,
        padding,
        resize,
    );

    // Resolve self-intersections (and curves that cross between paths) by
    // splitting at the crossing and re-routing the topology so each output
    // sub-path is simple. Cheap when nothing crosses (just AABB checks per
    // pair); only does real subdivision work when AABBs actually overlap.
    // Tolerance is half a texel of the final scale, so any approximation
    // error is invisible without zooming way in.
    const tolerance = 0.5 / sdf_tex.scale;
    const resolved_paths = try resolveSelfIntersections(paths, std.heap.page_allocator, tolerance);

    // Force every path to wind clockwise BEFORE we scale into texel space. The
    // SDF fragment shader picks the fill side from the tangent's half-plane
    // (see ADRs/SDF rendering and drawShape/base.wgsl); mixing winding makes
    // some paths render as inverted holes. Doing it here — while paths are
    // still separate — means we never have to detect path boundaries inside a
    // flat buffer.
    ensureClockwiseOrientation(resolved_paths);

    // Now that every path is CW, walk the containment hierarchy and flip any
    // path whose nesting depth is odd back to CCW. That gives us "e", "o", "q"
    // style holes for free, and also makes self-intersection resolution
    // produce holes when one of the resulting sub-paths is contained in the
    // other (e.g. a curve that loops back inside itself).
    fixHoleWinding(resolved_paths);

    // Flatten the paths into one contiguous buffer so the rest of the function
    // (scaling, arc-length sampling, the webgpu dispatch) can stay exactly the
    // way it was before paths became explicit.
    var total_len: usize = 0;
    for (resolved_paths) |path| total_len += path.len;
    const points = try std.heap.page_allocator.alloc(types.Point, total_len);
    {
        var offset: usize = 0;
        for (resolved_paths) |path| {
            @memcpy(points[offset .. offset + path.len], path);
            offset += path.len;
        }
    }

    // jsut happened that we want 4 sampels per curve and also we have 4 poitns per curve, it's coincidence
    const uniform_t_list = try std.heap.page_allocator.alloc(f32, points.len + 1);
    uniform_t_list[0] = 0;

    for (points, 0..) |*point, i| {
        _ = i; // autofix
        if (path_utils.isStraightLineHandle(point.*)) {
            // if (i % 4 == 1) {
            //     point.x = points[i - 1].x;
            //     point.y = points[i - 1].y;

            //     continue; // this point already was multiplied by computations below
            //     // avoid doign it again
            // } else if (i % 4 == 2) {
            //     // not sure if that case is even possible
            //     point.x = points[i + 1].x;
            //     point.y = points[i + 1].y;
            // } else {
            //     @panic("Unexpected handle inde");
            // }
            continue;
        }

        point.x *= sdf_tex.scale;
        point.y *= sdf_tex.scale;

        point.x += consts.SDF_SAFE_PADDING + sdf_tex.padding;
        point.y += consts.SDF_SAFE_PADDING + sdf_tex.padding;
    }

    sdf_tex.points = points;
    sdf_tex.valid = points.len > 0;

    // Fill uniform_t_list: cumulative arc length at t=0.25, 0.50, 0.75, 1.00 for each curve.
    // Points are already in texel space at this point.
    const num_curves = points.len / 4;
    var cumulative: f32 = 0;
    for (0..num_curves) |ci| {
        const p0 = points[ci * 4 + 0];
        const p1 = points[ci * 4 + 1];
        const p2 = points[ci * 4 + 2];
        const p3 = points[ci * 4 + 3];
        const is_straight = path_utils.isStraightLineHandle(points[ci * 4 + 1]);

        // Sample arc length at t = 0.25, 0.50, 0.75, 1.00 using 16 linear segments per quarter.
        const segments_per_quarter: u32 = 4;
        var prev = p0;
        for (0..4) |quarter| {
            const t_start: f32 = @as(f32, @floatFromInt(quarter)) * 0.25;
            const t_end: f32 = t_start + 0.25;
            for (1..segments_per_quarter + 1) |s| {
                const t = t_start + (t_end - t_start) * @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(segments_per_quarter));
                const pt = if (is_straight) blk: {
                    // linear interpolation between p0 and p3
                    break :blk types.Point{
                        .x = p0.x + (p3.x - p0.x) * t,
                        .y = p0.y + (p3.y - p0.y) * t,
                    };
                } else blk: {
                    const mt = 1.0 - t;
                    break :blk types.Point{
                        .x = mt * mt * mt * p0.x + 3 * mt * mt * t * p1.x + 3 * mt * t * t * p2.x + t * t * t * p3.x,
                        .y = mt * mt * mt * p0.y + 3 * mt * mt * t * p1.y + 3 * mt * t * t * p2.y + t * t * t * p3.y,
                    };
                };
                cumulative += prev.distance(pt);
                prev = pt;
            }
            uniform_t_list[ci * 4 + quarter + 1] = cumulative;
        }
    }
    sdf_tex.uniform_t = uniform_t_list;

    webgpu_glue.compute_shape(
        sdf_tex.points,
        @intFromFloat(sdf_tex.size.w),
        @intFromFloat(sdf_tex.size.h),
        sdf_tex.id,
    );

    return sdf_tex;
}

// Reverses any path that is not clockwise. Each `path` is a flat slice of
// 4-point cubic-bezier segments [p0, p1, p2, p3, ...] and is assumed to be
// already closed (curves[K].p3 == curves[K+1].p0 within the path, and the last
// curve's p3 == the first curve's p0).
//
// "Clockwise" here means the visual clockwise direction under the codebase's
// y-axis-up convention (see ADRs/y-axis coords). In y-up math that direction
// has NEGATIVE signed area, so we flip whenever the signed area is positive.
fn ensureClockwiseOrientation(paths: [][]types.Point) void {
    for (paths) |path| {
        if (signedArea(path) > 0) {
            reversePath(path);
        }
    }
}

// Signed area of the polygon formed by the curve endpoints (p0 → p3 of every
// curve). For any non-self-intersecting closed bezier path the SIGN of this
// polygon's area matches the sign of the region the curves actually enclose,
// so the off-curve handles p1/p2 don't need to be sampled.
fn signedArea(path: []const types.Point) f32 {
    var doubled_area: f32 = 0;
    const num_curves = path.len / 4;
    var ci: usize = 0;
    while (ci < num_curves) : (ci += 1) {
        const a = path[ci * 4 + 0];
        const b = path[ci * 4 + 3];
        doubled_area += a.x * b.y - b.x * a.y;
    }
    return doubled_area * 0.5;
}

// Flips any path whose nesting depth is odd. Run AFTER
// ensureClockwiseOrientation, so on entry every path is CW; on exit, depth-0
// paths are CW (fill), depth-1 are CCW (hole), depth-2 are CW (fill within
// hole), and so on. The shader's tangent half-plane test then renders nested
// regions as alternating fill/hole, which is what we want for letters like
// "e", "o", "q" drawn as outer-plus-inner contours.
//
// SCOPE
//   This handles the common case where paths are nested but DO NOT cross each
//   other. Self-intersection or curves crossing other curves is a separate
//   problem (full boolean ops) and is intentionally not addressed here — that
//   would require splitting curves at intersection points and re-routing the
//   topology, which is a much larger piece of work.
//
// COST
//   O(N²) over the number of paths, with N typically ≤ a handful per shape.
//   The constant is tiny (one ray-cross test per pair). Not worth a spatial
//   index until profiling says so.
fn fixHoleWinding(paths: [][]types.Point) void {
    for (paths, 0..) |path, i| {
        if (path.len < 4) continue;
        if (nestingDepth(paths, i) % 2 == 1) {
            reversePath(path);
        }
    }
}

// Counts how many OTHER paths contain `paths[self_idx]`. Picks the test point
// as the first curve's p0 — that point lies exactly on the path, but since we
// assume paths don't cross, it's either fully inside or fully outside every
// other path, so a single sample is enough.
fn nestingDepth(paths: [][]types.Point, self_idx: usize) usize {
    if (paths[self_idx].len < 4) return 0;
    const test_point = paths[self_idx][0];

    var depth: usize = 0;
    for (paths, 0..) |other, j| {
        if (j == self_idx) continue;
        if (isPointInsidePath(test_point, other)) depth += 1;
    }
    return depth;
}

// Standard horizontal-ray-crossing point-in-polygon test, run on the polygon
// formed by the p0 of every curve. Each pair of consecutive curve starts
// (with wraparound) defines one polygon edge; we count edges that cross the
// ray going from `point` toward +x and return true if the count is odd.
//
// The polygon is an approximation of the bezier path — the curves' off-line
// bulges are ignored. That's fine for typical user input (the inner contour
// of an "o" sits well inside the outer's polygon), and matches the same
// approximation we use in signedArea. If a future shape pathologically lands
// a test point in the gap between a curve and its chord, this test will
// misjudge it; the upgrade path is to replace each polygon edge with a real
// cubic-vs-horizontal-line crossing count (closed-form, just more code).
fn isPointInsidePath(point: types.Point, path: []const types.Point) bool {
    const num_curves = path.len / 4;
    if (num_curves < 3) return false; // not enough vertices to enclose anything

    var inside = false;
    var i: usize = 0;
    var j: usize = num_curves - 1;
    while (i < num_curves) : (i += 1) {
        const a = path[i * 4];
        const b = path[j * 4];
        // Edge from a to b (or b to a — orientation doesn't affect crossing
        // count). Only count it if the edge straddles the horizontal line at
        // point.y; the strict inequality handles the "ray grazing a vertex"
        // edge case correctly under the usual point-in-polygon convention.
        const crosses_y = (a.y > point.y) != (b.y > point.y);
        if (crosses_y) {
            const x_at_point_y = a.x + (b.x - a.x) * (point.y - a.y) / (b.y - a.y);
            if (point.x < x_at_point_y) inside = !inside;
        }
        j = i;
    }
    return inside;
}

// =============================================================================
// Self-intersection resolution
//
// When a path crosses itself (or two paths cross each other), the SDF tangent
// fill test smears across the crossing because the fragment can't tell which
// curve to side-test against. We fix it before SDF baking: find every place
// curves cross, split each curve at the crossing, and rewire the path so that
// at each crossing the two "out" branches swap which "in" branch they connect
// to. That single swap turns one self-intersecting loop into two clean,
// simple-closed loops, which the existing fill code handles fine.
//
// PRECISION
//   Bezier subdivision intersection with termination at `tolerance` (half a
//   texel of the final scale, computed by the caller). Any error in the
//   crossing point is sub-pixel — visible only with significant zoom.
//
// PERFORMANCE
//   For paths that don't cross anything (the overwhelming common case), the
//   work is one AABB-overlap test per curve pair within a path — O(N²) min/
//   max comparisons, no allocation, no recursion. Subdivision is only entered
//   when AABBs actually overlap, and even then each level halves both curves
//   and only recurses into the four sub-pairs whose AABBs still overlap.
//
// SCOPE
//   Handles self-intersections within a path AND crossings between paths
//   (because we feed every pair into the same finder). Doesn't handle
//   tangent-but-not-crossing kisses cleanly — those produce a near-zero
//   t-value split which we filter as a degenerate. Acceptable for our "good
//   enough at normal zoom" target.
// =============================================================================

const Cubic = struct {
    p0: types.Point,
    p1: types.Point,
    p2: types.Point,
    p3: types.Point,
};

const SelfHit = struct {
    curve_i: usize,
    curve_j: usize,
    t_i: f32,
    t_j: f32,
};

// Returns a freshly-allocated paths slice in which every path is simple
// (non-self-intersecting). Paths that already are simple are duplicated
// unchanged. The caller takes ownership of both the outer slice and every
// inner path slice.
fn resolveSelfIntersections(
    paths: [][]types.Point,
    allocator: std.mem.Allocator,
    tolerance: f32,
) ![][]types.Point {
    var output = std.ArrayList([]types.Point).init(allocator);
    for (paths) |path| {
        try resolvePath(path, &output, allocator, tolerance, 0);
    }
    return output.toOwnedSlice();
}

// Recursive worker: find one self-intersection, split the path in two, and
// recurse on each half. Each split strictly reduces self-crossings, so we
// converge — but we cap depth as a safety net in case floating-point noise
// somehow re-introduces an intersection.
fn resolvePath(
    path: []const types.Point,
    output: *std.ArrayList([]types.Point),
    allocator: std.mem.Allocator,
    tolerance: f32,
    depth: u32,
) !void {
    const MAX_DEPTH: u32 = 16; // 2^16 sub-paths from one input — pathological is a strong word for that

    if (depth < MAX_DEPTH) {
        if (findSelfIntersection(path, tolerance)) |hit| {
            const split = try splitAtSelfHit(path, hit, allocator);
            defer allocator.free(split.path_a);
            defer allocator.free(split.path_b);
            try resolvePath(split.path_a, output, allocator, tolerance, depth + 1);
            try resolvePath(split.path_b, output, allocator, tolerance, depth + 1);
            return;
        }
    }

    // No (more) intersections, or depth-cap reached. Emit the path as-is.
    const path_copy = try allocator.dupe(types.Point, path);
    try output.append(path_copy);
}

// Scans every non-adjacent pair of curves in `path` and returns the first
// crossing it finds. Adjacent pairs share a curve joint, which would look
// like an "intersection" at t≈0 or t≈1 of the joining curve — those are
// filtered both by the adjacency check and by the t-endpoint guard.
fn findSelfIntersection(path: []const types.Point, tolerance: f32) ?SelfHit {
    const num_curves = path.len / 4;
    if (num_curves < 2) return null;

    const T_ENDPOINT_EPS: f32 = 1e-3;

    var i: usize = 0;
    while (i < num_curves) : (i += 1) {
        var j: usize = i + 1;
        while (j < num_curves) : (j += 1) {
            if (areAdjacent(i, j, num_curves)) continue;

            const a = realCurve(path, i);
            const b = realCurve(path, j);

            if (intersectCubics(a, b, 0, 1, 0, 1, tolerance, 0)) |hit| {
                // Filter near-endpoint hits: those are tangent kisses at
                // curve junctions, not real crossings, and splitting there
                // produces a degenerate near-zero-length sub-curve.
                if (hit.t_i < T_ENDPOINT_EPS or hit.t_i > 1.0 - T_ENDPOINT_EPS) continue;
                if (hit.t_j < T_ENDPOINT_EPS or hit.t_j > 1.0 - T_ENDPOINT_EPS) continue;

                return SelfHit{
                    .curve_i = i,
                    .curve_j = j,
                    .t_i = hit.t_i,
                    .t_j = hit.t_j,
                };
            }
        }
    }
    return null;
}

inline fn areAdjacent(i: usize, j: usize, num_curves: usize) bool {
    // The path is closed, so curve N-1 is adjacent to curve 0 too.
    return j == i + 1 or (i == 0 and j + 1 == num_curves);
}

// Pulls a curve out of the flat path buffer, substituting collinear handles
// for the STRAIGHT_LINE_HANDLE marker. The "cubic" we hand to the math below
// is geometrically identical to the line p0→p3 in the straight case, so the
// intersection / split code doesn't need a straight-line special case.
fn realCurve(path: []const types.Point, idx: usize) Cubic {
    const p0 = path[idx * 4 + 0];
    const p1_raw = path[idx * 4 + 1];
    const p2_raw = path[idx * 4 + 2];
    const p3 = path[idx * 4 + 3];

    if (path_utils.isStraightLineHandle(p1_raw)) {
        return Cubic{
            .p0 = p0,
            .p1 = lerp(p0, p3, 1.0 / 3.0),
            .p2 = lerp(p0, p3, 2.0 / 3.0),
            .p3 = p3,
        };
    }
    return Cubic{ .p0 = p0, .p1 = p1_raw, .p2 = p2_raw, .p3 = p3 };
}

inline fn lerp(a: types.Point, b: types.Point, t: f32) types.Point {
    return types.Point{
        .x = a.x + (b.x - a.x) * t,
        .y = a.y + (b.y - a.y) * t,
    };
}

const Hit = struct { t_i: f32, t_j: f32 };

// Recursive AABB-subdivision intersection finder. Each call halves both
// curves with de Casteljau, then recurses into the four sub-pairs whose
// AABBs overlap. Termination: AABBs separated (no hit) or both AABBs smaller
// than `tolerance` (hit at the centre). Returns at most one hit, the first
// one the recursion finds — multiple hits between the same curve pair get
// discovered on subsequent passes after we split.
fn intersectCubics(
    a: Cubic,
    b: Cubic,
    a_t_lo: f32,
    a_t_hi: f32,
    b_t_lo: f32,
    b_t_hi: f32,
    tolerance: f32,
    depth: u32,
) ?Hit {
    if (!aabbOverlap(a, b)) return null;

    const a_size = aabbMaxDim(a);
    const b_size = aabbMaxDim(b);

    if (a_size < tolerance and b_size < tolerance) {
        return Hit{
            .t_i = (a_t_lo + a_t_hi) * 0.5,
            .t_j = (b_t_lo + b_t_hi) * 0.5,
        };
    }

    const MAX_DEPTH: u32 = 24;
    if (depth >= MAX_DEPTH) {
        return Hit{
            .t_i = (a_t_lo + a_t_hi) * 0.5,
            .t_j = (b_t_lo + b_t_hi) * 0.5,
        };
    }

    const a_split = splitAt(a, 0.5);
    const b_split = splitAt(b, 0.5);
    const a_t_mid = (a_t_lo + a_t_hi) * 0.5;
    const b_t_mid = (b_t_lo + b_t_hi) * 0.5;

    if (intersectCubics(a_split.first, b_split.first, a_t_lo, a_t_mid, b_t_lo, b_t_mid, tolerance, depth + 1)) |h| return h;
    if (intersectCubics(a_split.first, b_split.second, a_t_lo, a_t_mid, b_t_mid, b_t_hi, tolerance, depth + 1)) |h| return h;
    if (intersectCubics(a_split.second, b_split.first, a_t_mid, a_t_hi, b_t_lo, b_t_mid, tolerance, depth + 1)) |h| return h;
    if (intersectCubics(a_split.second, b_split.second, a_t_mid, a_t_hi, b_t_mid, b_t_hi, tolerance, depth + 1)) |h| return h;

    return null;
}

fn aabbOverlap(a: Cubic, b: Cubic) bool {
    const a_min_x = @min(@min(a.p0.x, a.p1.x), @min(a.p2.x, a.p3.x));
    const a_max_x = @max(@max(a.p0.x, a.p1.x), @max(a.p2.x, a.p3.x));
    const a_min_y = @min(@min(a.p0.y, a.p1.y), @min(a.p2.y, a.p3.y));
    const a_max_y = @max(@max(a.p0.y, a.p1.y), @max(a.p2.y, a.p3.y));
    const b_min_x = @min(@min(b.p0.x, b.p1.x), @min(b.p2.x, b.p3.x));
    const b_max_x = @max(@max(b.p0.x, b.p1.x), @max(b.p2.x, b.p3.x));
    const b_min_y = @min(@min(b.p0.y, b.p1.y), @min(b.p2.y, b.p3.y));
    const b_max_y = @max(@max(b.p0.y, b.p1.y), @max(b.p2.y, b.p3.y));

    return a_min_x <= b_max_x and a_max_x >= b_min_x and
        a_min_y <= b_max_y and a_max_y >= b_min_y;
}

fn aabbMaxDim(c: Cubic) f32 {
    const min_x = @min(@min(c.p0.x, c.p1.x), @min(c.p2.x, c.p3.x));
    const max_x = @max(@max(c.p0.x, c.p1.x), @max(c.p2.x, c.p3.x));
    const min_y = @min(@min(c.p0.y, c.p1.y), @min(c.p2.y, c.p3.y));
    const max_y = @max(@max(c.p0.y, c.p1.y), @max(c.p2.y, c.p3.y));
    return @max(max_x - min_x, max_y - min_y);
}

const SplitPair = struct { first: Cubic, second: Cubic };

// de Casteljau split at parameter t. The two output cubics meet exactly at
// the curve point P(t) — that shared endpoint is what lets us snap the two
// resulting paths to the same crossing point.
fn splitAt(c: Cubic, t: f32) SplitPair {
    const q0 = lerp(c.p0, c.p1, t);
    const q1 = lerp(c.p1, c.p2, t);
    const q2 = lerp(c.p2, c.p3, t);
    const r0 = lerp(q0, q1, t);
    const r1 = lerp(q1, q2, t);
    const s = lerp(r0, r1, t);
    return SplitPair{
        .first = Cubic{ .p0 = c.p0, .p1 = q0, .p2 = r0, .p3 = s },
        .second = Cubic{ .p0 = s, .p1 = r1, .p2 = q2, .p3 = c.p3 },
    };
}

const PathSplit = struct {
    path_a: []types.Point,
    path_b: []types.Point,
};

// Splits a self-intersecting path into two simple sub-paths at the given
// crossing. Topology re-route: if the original path runs
//     ... → C[i-1] → C_i → C[i+1] → ... → C[j-1] → C_j → C[j+1] → ...
// (closed back to C[0]) and C_i × C_j cross at point P at t_i, t_j, then:
//
//     path_a = C_i_pre, C_j_post, C[j+1..N), C[0..i)
//     path_b = C_i_post, C[i+1..j), C_j_pre
//
// Both close cleanly because both C_i_pre.p3 and C_j_pre.p3 are snapped to
// the same midpoint of the two split endpoints (subdivision gives them as
// nearly-equal points; we average them so each output path is exactly closed).
fn splitAtSelfHit(
    path: []const types.Point,
    hit: SelfHit,
    allocator: std.mem.Allocator,
) !PathSplit {
    const num_curves = path.len / 4;

    const c_i = realCurve(path, hit.curve_i);
    const c_j = realCurve(path, hit.curve_j);

    const split_i = splitAt(c_i, hit.t_i);
    const split_j = splitAt(c_j, hit.t_j);

    // The two split endpoints should be (approximately) the crossing point;
    // average them to get a single P that both output paths will share.
    const P = types.Point{
        .x = (split_i.first.p3.x + split_j.first.p3.x) * 0.5,
        .y = (split_i.first.p3.y + split_j.first.p3.y) * 0.5,
    };

    var c_i_pre = split_i.first;
    var c_i_post = split_i.second;
    var c_j_pre = split_j.first;
    var c_j_post = split_j.second;
    c_i_pre.p3 = P;
    c_i_post.p0 = P;
    c_j_pre.p3 = P;
    c_j_post.p0 = P;

    // path_a curve count: c_i_pre + c_j_post + curves[j+1..N) + curves[0..i)
    // path_b curve count: c_i_post + curves[i+1..j) + c_j_pre
    const path_a_curves = 2 + (num_curves - 1 - hit.curve_j) + hit.curve_i;
    const path_b_curves = 2 + (hit.curve_j - hit.curve_i - 1);

    const path_a = try allocator.alloc(types.Point, path_a_curves * 4);
    const path_b = try allocator.alloc(types.Point, path_b_curves * 4);

    // Fill path_a
    var w: usize = 0;
    writeCurve(path_a, &w, c_i_pre);
    writeCurve(path_a, &w, c_j_post);
    var k: usize = hit.curve_j + 1;
    while (k < num_curves) : (k += 1) {
        copyCurve(path_a, &w, path, k);
    }
    k = 0;
    while (k < hit.curve_i) : (k += 1) {
        copyCurve(path_a, &w, path, k);
    }

    // Fill path_b
    w = 0;
    writeCurve(path_b, &w, c_i_post);
    k = hit.curve_i + 1;
    while (k < hit.curve_j) : (k += 1) {
        copyCurve(path_b, &w, path, k);
    }
    writeCurve(path_b, &w, c_j_pre);

    return PathSplit{ .path_a = path_a, .path_b = path_b };
}

fn writeCurve(out: []types.Point, w: *usize, c: Cubic) void {
    out[w.*] = c.p0;
    out[w.* + 1] = c.p1;
    out[w.* + 2] = c.p2;
    out[w.* + 3] = c.p3;
    w.* += 4;
}

fn copyCurve(out: []types.Point, w: *usize, src: []const types.Point, idx: usize) void {
    out[w.*] = src[idx * 4 + 0];
    out[w.* + 1] = src[idx * 4 + 1];
    out[w.* + 2] = src[idx * 4 + 2];
    out[w.* + 3] = src[idx * 4 + 3];
    w.* += 4;
}

// Reverses a path's curves in place while preserving the geometry: the curve
// order is reversed, then within each curve p0<->p3 and p1<->p2 are swapped.
// Together that flips t -> (1-t) on every curve and walks them back-to-front,
// which is exactly what reversing the path direction means.
//
// Full-straight curves carry the STRAIGHT_LINE_HANDLE marker on BOTH p1 and
// p2 (prepareHalfStraightLines guarantees this), so the inner swap is a no-op
// and the marker survives. Shared endpoints across adjacent curves are still
// shared after the reversal, so the path remains closed.
fn reversePath(path: []types.Point) void {
    const num_curves = path.len / 4;
    if (num_curves == 0) return;

    // Step 1: reverse curve order, pairing index n with (num_curves - 1 - n)
    // and stopping at the midpoint. For odd `num_curves` the middle curve has
    // no partner and is skipped — exactly what we want.
    var n: usize = 0;
    while (n < num_curves / 2) : (n += 1) {
        const j = num_curves - 1 - n;
        var k: usize = 0;
        while (k < 4) : (k += 1) {
            const tmp = path[n * 4 + k];
            path[n * 4 + k] = path[j * 4 + k];
            path[j * 4 + k] = tmp;
        }
    }

    // Step 2: within each curve, swap (p0, p3) and (p1, p2).
    var ci: usize = 0;
    while (ci < num_curves) : (ci += 1) {
        const old_p0 = path[ci * 4 + 0];
        const old_p1 = path[ci * 4 + 1];
        path[ci * 4 + 0] = path[ci * 4 + 3];
        path[ci * 4 + 3] = old_p0;
        path[ci * 4 + 1] = path[ci * 4 + 2];
        path[ci * 4 + 2] = old_p1;
    }
}
