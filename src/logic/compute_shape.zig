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

    // Split any self-crossing path into its Seifert-smoothed sub-paths BEFORE
    // we touch winding. A figure-8 entered as one path would otherwise have
    // the shader's tangent test flip polarity at every crossing — the magenta
    // "inside" of the reference shape ends up split into bands. After the
    // split each sub-path is non-self-crossing, so the CW/hole-flip steps
    // below can do their normal job.
    const working_paths: [][]types.Point = blk: {
        var split = std.ArrayList([]types.Point).init(std.heap.page_allocator);
        for (paths) |p| {
            const subs = try splitAtSelfIntersections(p, std.heap.page_allocator);
            try split.appendSlice(subs);
            std.heap.page_allocator.free(subs);
        }
        break :blk try split.toOwnedSlice();
    };

    // Force every path to wind clockwise BEFORE we scale into texel space. The
    // SDF fragment shader picks the fill side from the tangent's half-plane
    // (see ADRs/SDF rendering and drawShape/base.wgsl); mixing winding makes
    // some paths render as inverted holes. Doing it here — while paths are
    // still separate — means we never have to detect path boundaries inside a
    // flat buffer.
    ensureClockwiseOrientation(working_paths);

    // Now that every path is CW, walk the containment hierarchy and flip any
    // path whose nesting depth is odd back to CCW. That gives us "e", "o", "q"
    // style holes for free: outer contour stays a fill, the inner contour
    // becomes the opposite winding, and the shader's tangent test reports the
    // hole region as outside.
    fixHoleWinding(working_paths);

    // Flatten the paths into one contiguous buffer so the rest of the function
    // (scaling, arc-length sampling, the webgpu dispatch) can stay exactly the
    // way it was before paths became explicit.
    var total_len: usize = 0;
    for (working_paths) |path| total_len += path.len;
    const points = try std.heap.page_allocator.alloc(types.Point, total_len);
    {
        var offset: usize = 0;
        for (working_paths) |path| {
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
// SELF-INTERSECTION SPLITTING
// =============================================================================
// `fixHoleWinding` (above) handles the easy case where paths nest but never
// cross. When a SINGLE path crosses itself, the tangent-based fill in the
// shader gets confused — at every crossing the inside/outside labelling
// flips polarity (see ADRs/SDF rendering). The reference shape that
// motivated this routine is a double figure-8: one path with two transverse
// self-crossings, where the magenta "inside" should be the union of three
// disjoint loops, not a single crossing path.
//
// `splitAtSelfIntersections` rewrites that one crossing path into K+1 closed
// sub-paths (K = number of transverse self-crossings) by Seifert-smoothing
// every crossing. Each smoothed loop is non-self-crossing on its own, so
// the existing CW-orientation + hole-flip pipeline can take it from there.
//
// PUBLIC ENTRY POINT
//   splitAtSelfIntersections(path, allocator) -> [][]Point
//
// Caller owns the result and every inner slice (free with the same allocator
// that was passed in). Paths with no self-crossings come back as a one-element
// array so callers can treat the output uniformly.

/// pixels of bbox edge at which we accept a crossing — small enough that the
/// snap-together step at the end stays sub-pixel, large enough that we never
/// chase floating-point noise.
const SUBDIVISION_TOLERANCE: f32 = 0.05;
const MAX_SUBDIVISION_DEPTH: u32 = 32;
/// distance below which two crossing candidates are treated as the same one;
/// recursion can bracket a single crossing from both sides.
const SAME_INTERSECTION_DIST: f32 = 0.5;
const ENDPOINT_T_EPS: f32 = 1e-3;

const Intersection = struct {
    curve_a: u32,
    curve_b: u32,
    t_a: f32,
    t_b: f32,
    point: types.Point,
};

/// What sits on one side of a stub. Either it abuts the previous/next stub
/// in the original path order (`.continuation`), or it ends at intersection
/// `id`, where the Seifert swap will route it across to the other curve.
const StubBoundary = union(enum) {
    continuation,
    intersection: u32,
};

const Stub = struct {
    points: [4]types.Point,
    is_straight: bool,
    prev_kind: StubBoundary,
    next_kind: StubBoundary,
    curve_idx: u32,
};

/// Bookkeeping for a single crossing: which stubs arrive at it (one per
/// crossing curve) and which stubs leave it. Filled while we cut the curves;
/// read while we walk the resulting graph.
const IntersectionEnds = struct {
    incoming_a: u32 = 0,
    outgoing_a: u32 = 0,
    incoming_b: u32 = 0,
    outgoing_b: u32 = 0,
};

/// A sub-arc of an original cubic bezier, parameterised by [t_min, t_max] in
/// the original curve's t-space. Used during the recursive-bisection
/// intersection search.
const SubBox = struct {
    p0: types.Point,
    p1: types.Point,
    p2: types.Point,
    p3: types.Point,
    is_straight: bool,
    t_min: f32,
    t_max: f32,
};

const TStop = struct {
    t: f32,
    intersection_id: u32,
};

fn pointLerp(a: types.Point, b: types.Point, t: f32) types.Point {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
}

/// De Casteljau split of a cubic at parameter t. `left` covers [0, t],
/// `right` covers [t, 1]; `left[3] == right[0]` by construction so the
/// halves stitch back together exactly.
fn splitCubic(
    p0: types.Point,
    p1: types.Point,
    p2: types.Point,
    p3: types.Point,
    t: f32,
    left: *[4]types.Point,
    right: *[4]types.Point,
) void {
    const a = pointLerp(p0, p1, t);
    const b = pointLerp(p1, p2, t);
    const c = pointLerp(p2, p3, t);
    const d = pointLerp(a, b, t);
    const e = pointLerp(b, c, t);
    const f = pointLerp(d, e, t);
    left.* = .{ p0, a, d, f };
    right.* = .{ f, e, c, p3 };
}

fn boundingBox(b: SubBox) [4]f32 {
    if (b.is_straight) {
        return .{
            @min(b.p0.x, b.p3.x), @min(b.p0.y, b.p3.y),
            @max(b.p0.x, b.p3.x), @max(b.p0.y, b.p3.y),
        };
    }
    return .{
        @min(@min(b.p0.x, b.p1.x), @min(b.p2.x, b.p3.x)),
        @min(@min(b.p0.y, b.p1.y), @min(b.p2.y, b.p3.y)),
        @max(@max(b.p0.x, b.p1.x), @max(b.p2.x, b.p3.x)),
        @max(@max(b.p0.y, b.p1.y), @max(b.p2.y, b.p3.y)),
    };
}

fn boxesOverlap(a: [4]f32, b: [4]f32) bool {
    return a[0] <= b[2] and a[2] >= b[0] and a[1] <= b[3] and a[3] >= b[1];
}

fn boxLargestSide(b: [4]f32) f32 {
    return @max(b[2] - b[0], b[3] - b[1]);
}

fn subdivideBox(b: SubBox) [2]SubBox {
    const t_mid = (b.t_min + b.t_max) * 0.5;
    if (b.is_straight) {
        const m = pointLerp(b.p0, b.p3, 0.5);
        return .{
            .{
                .p0 = b.p0,
                .p1 = path_utils.STRAIGHT_LINE_HANDLE,
                .p2 = path_utils.STRAIGHT_LINE_HANDLE,
                .p3 = m,
                .is_straight = true,
                .t_min = b.t_min,
                .t_max = t_mid,
            },
            .{
                .p0 = m,
                .p1 = path_utils.STRAIGHT_LINE_HANDLE,
                .p2 = path_utils.STRAIGHT_LINE_HANDLE,
                .p3 = b.p3,
                .is_straight = true,
                .t_min = t_mid,
                .t_max = b.t_max,
            },
        };
    }
    var left: [4]types.Point = undefined;
    var right: [4]types.Point = undefined;
    splitCubic(b.p0, b.p1, b.p2, b.p3, 0.5, &left, &right);
    return .{
        .{
            .p0 = left[0],
            .p1 = left[1],
            .p2 = left[2],
            .p3 = left[3],
            .is_straight = false,
            .t_min = b.t_min,
            .t_max = t_mid,
        },
        .{
            .p0 = right[0],
            .p1 = right[1],
            .p2 = right[2],
            .p3 = right[3],
            .is_straight = false,
            .t_min = t_mid,
            .t_max = b.t_max,
        },
    };
}

/// Recursively bisect two curves, halving whichever still has the larger
/// bounding box, and report a crossing whenever both bboxes have shrunk
/// below SUBDIVISION_TOLERANCE while still overlapping. The endpoint joints
/// between consecutive curves (and the wrap joint at the seam) are not real
/// crossings — they're just the shared p0/p3 of the path — and are filtered
/// out before we record anything.
fn findCurvePairIntersections(
    a: SubBox,
    b: SubBox,
    ci: u32,
    cj: u32,
    adjacent_forward: bool,
    adjacent_wrap: bool,
    depth: u32,
    out: *std.ArrayList(Intersection),
) !void {
    const a_bb = boundingBox(a);
    const b_bb = boundingBox(b);
    if (!boxesOverlap(a_bb, b_bb)) return;

    const a_size = boxLargestSide(a_bb);
    const b_size = boxLargestSide(b_bb);

    if ((a_size < SUBDIVISION_TOLERANCE and b_size < SUBDIVISION_TOLERANCE) or depth >= MAX_SUBDIVISION_DEPTH) {
        const t_a = (a.t_min + a.t_max) * 0.5;
        const t_b = (b.t_min + b.t_max) * 0.5;

        // Drop the trivial endpoint joins between consecutive curves.
        if (adjacent_forward and t_a > 1.0 - ENDPOINT_T_EPS and t_b < ENDPOINT_T_EPS) return;
        if (adjacent_wrap and t_b > 1.0 - ENDPOINT_T_EPS and t_a < ENDPOINT_T_EPS) return;

        const point: types.Point = .{
            .x = (a_bb[0] + a_bb[2]) * 0.5,
            .y = (a_bb[1] + a_bb[3]) * 0.5,
        };

        // Recursion can bracket the same crossing from both halves of a
        // subdivided box; collapse near-duplicates here.
        for (out.items) |existing| {
            if (existing.curve_a == ci and existing.curve_b == cj and
                existing.point.distance(point) < SAME_INTERSECTION_DIST)
            {
                return;
            }
        }

        try out.append(.{
            .curve_a = ci,
            .curve_b = cj,
            .t_a = t_a,
            .t_b = t_b,
            .point = point,
        });
        return;
    }

    if (a_size >= b_size) {
        const halves = subdivideBox(a);
        try findCurvePairIntersections(halves[0], b, ci, cj, adjacent_forward, adjacent_wrap, depth + 1, out);
        try findCurvePairIntersections(halves[1], b, ci, cj, adjacent_forward, adjacent_wrap, depth + 1, out);
    } else {
        const halves = subdivideBox(b);
        try findCurvePairIntersections(a, halves[0], ci, cj, adjacent_forward, adjacent_wrap, depth + 1, out);
        try findCurvePairIntersections(a, halves[1], ci, cj, adjacent_forward, adjacent_wrap, depth + 1, out);
    }
}

fn lessTStop(_: void, a: TStop, b: TStop) bool {
    return a.t < b.t;
}

fn cloneAsSinglePath(path: []const types.Point, allocator: std.mem.Allocator) ![][]types.Point {
    const result = try allocator.alloc([]types.Point, 1);
    result[0] = try allocator.alloc(types.Point, path.len);
    @memcpy(result[0], path);
    return result;
}

/// Splits a closed cubic-bezier path at every transverse self-crossing into
/// multiple closed sub-paths. K crossings produce K+1 sub-paths: a figure-8
/// (1 crossing) becomes 2 loops, the double figure-8 from the reference
/// image (2 crossings) becomes 3 loops, and so on. If the input has no
/// crossings the function returns a single-element array containing a copy
/// of the input.
///
/// INPUT
///   `path` is a flat slice of cubic-bezier control points
///   [p0, p1, p2, p3, p0, p1, p2, p3, ...] where consecutive curves share an
///   endpoint by value (curve K's p3 == curve K+1's p0) and the last p3
///   equals the first p0 — i.e. the path is already closed. Straight-line
///   segments must carry STRAIGHT_LINE_HANDLE on BOTH p1 and p2; run
///   `prepareHalfStraightLines` first to normalise half-straight inputs.
///
/// METHOD
///   1. For every (i, j) curve pair we recursively bisect both curves and
///      drop branches whose bounding boxes don't overlap. Once both boxes
///      shrink below SUBDIVISION_TOLERANCE we record one crossing. The
///      endpoint joints between adjacent curves and at the wrap-around seam
///      are filtered out — they're shared p0/p3, not real crossings. A
///      small dedupe table catches the same crossing arrived at from two
///      sides of an earlier split.
///   2. For each curve, gather the t-parameters of crossings that land on
///      it, sort them ascending, and slice the curve via De Casteljau into
///      one stub per gap. Cut parameters are remapped into the remaining
///      curve's local [0, 1] each iteration so geometry stays correct
///      after multiple cuts on the same curve.
///   3. At every crossing four stub ends meet: in/out on curve a, in/out on
///      curve b. We Seifert-smooth the joint — incoming-a links to
///      outgoing-b and incoming-b links to outgoing-a — which is the
///      resolution that turns a figure-8 into two non-crossing loops. The
///      four endpoint coordinates are also snapped to their average so the
///      output sub-paths stitch closed exactly (sub-pixel error from the
///      bisection would otherwise leave tiny gaps).
///   4. Walk the stubs. Each unvisited stub seeds one sub-path; from any
///      stub we follow either the natural path order (next_kind ==
///      .continuation, jump to the first stub of the next curve) or the
///      smoothed partner (next_kind == .intersection, jump across via the
///      `ends` table). Every stub ends up in exactly one sub-path, and
///      every sub-path is closed.
///
/// LIMITATIONS
///   - Tangent (non-transverse) crossings, triple points, and pairs of
///     curves that overlap along a segment are not handled cleanly. Some
///     get collapsed by the dedupe; others will produce degenerate stubs.
///     The right fix for those is a real boolean-ops engine. This routine
///     keeps the common transverse cases — figure-8, double figure-8,
///     star-style self-crossings — working.
///   - The function allocates the result through `allocator`. Every inner
///     slice is its own allocation; free them individually before freeing
///     the outer slice.
pub fn splitAtSelfIntersections(
    path: []const types.Point,
    allocator: std.mem.Allocator,
) ![][]types.Point {
    if (path.len == 0 or path.len % 4 != 0) {
        return cloneAsSinglePath(path, allocator);
    }
    const num_curves: u32 = @intCast(path.len / 4);
    if (num_curves < 2) {
        return cloneAsSinglePath(path, allocator);
    }

    // ---- step 1: find every self-crossing -------------------------------
    var intersections = std.ArrayList(Intersection).init(allocator);
    defer intersections.deinit();

    {
        var i: u32 = 0;
        while (i < num_curves) : (i += 1) {
            const a0 = path[i * 4 + 0];
            const a1 = path[i * 4 + 1];
            const a2 = path[i * 4 + 2];
            const a3 = path[i * 4 + 3];
            const a_straight = path_utils.isStraightLineHandle(a1) or path_utils.isStraightLineHandle(a2);
            const a_box: SubBox = .{
                .p0 = a0,
                .p1 = a1,
                .p2 = a2,
                .p3 = a3,
                .is_straight = a_straight,
                .t_min = 0,
                .t_max = 1,
            };

            var j: u32 = i + 1;
            while (j < num_curves) : (j += 1) {
                const b0 = path[j * 4 + 0];
                const b1 = path[j * 4 + 1];
                const b2 = path[j * 4 + 2];
                const b3 = path[j * 4 + 3];
                const b_straight = path_utils.isStraightLineHandle(b1) or path_utils.isStraightLineHandle(b2);
                const b_box: SubBox = .{
                    .p0 = b0,
                    .p1 = b1,
                    .p2 = b2,
                    .p3 = b3,
                    .is_straight = b_straight,
                    .t_min = 0,
                    .t_max = 1,
                };

                const adjacent_forward = (j == i + 1);
                const adjacent_wrap = (i == 0 and j == num_curves - 1);
                try findCurvePairIntersections(
                    a_box,
                    b_box,
                    i,
                    j,
                    adjacent_forward,
                    adjacent_wrap,
                    0,
                    &intersections,
                );
            }
        }
    }

    if (intersections.items.len == 0) {
        return cloneAsSinglePath(path, allocator);
    }

    // ---- step 2: per-curve sorted t-stops, then cut into stubs ----------
    const per_curve_ts = try allocator.alloc(std.ArrayList(TStop), num_curves);
    defer {
        for (per_curve_ts) |*ts| ts.deinit();
        allocator.free(per_curve_ts);
    }
    for (per_curve_ts) |*ts| ts.* = std.ArrayList(TStop).init(allocator);

    for (intersections.items, 0..) |x, idx| {
        try per_curve_ts[x.curve_a].append(.{ .t = x.t_a, .intersection_id = @intCast(idx) });
        try per_curve_ts[x.curve_b].append(.{ .t = x.t_b, .intersection_id = @intCast(idx) });
    }

    var stubs = std.ArrayList(Stub).init(allocator);
    defer stubs.deinit();

    var first_stub_of_curve = try allocator.alloc(u32, num_curves);
    defer allocator.free(first_stub_of_curve);

    var ends = try allocator.alloc(IntersectionEnds, intersections.items.len);
    defer allocator.free(ends);
    for (ends) |*e| e.* = .{};

    {
        var c: u32 = 0;
        while (c < num_curves) : (c += 1) {
            const p0 = path[c * 4 + 0];
            const p1 = path[c * 4 + 1];
            const p2 = path[c * 4 + 2];
            const p3 = path[c * 4 + 3];
            const is_straight = path_utils.isStraightLineHandle(p1) or path_utils.isStraightLineHandle(p2);

            std.sort.pdq(TStop, per_curve_ts[c].items, {}, lessTStop);
            const ts = per_curve_ts[c].items;
            first_stub_of_curve[c] = @intCast(stubs.items.len);

            // Peel left halves off a shrinking remainder, remapping each
            // global t into the remainder's local [0, 1].
            var rem_p0 = p0;
            var rem_p1 = p1;
            var rem_p2 = p2;
            var rem_p3 = p3;
            var prev_t: f32 = 0;

            for (ts, 0..) |stop, idx_in_curve| {
                const denom = 1.0 - prev_t;
                const local_t: f32 = if (denom > 1e-6) (stop.t - prev_t) / denom else 0.5;

                var left: [4]types.Point = undefined;
                var right: [4]types.Point = undefined;
                if (is_straight) {
                    const split_pt = pointLerp(rem_p0, rem_p3, local_t);
                    left = .{ rem_p0, path_utils.STRAIGHT_LINE_HANDLE, path_utils.STRAIGHT_LINE_HANDLE, split_pt };
                    right = .{ split_pt, path_utils.STRAIGHT_LINE_HANDLE, path_utils.STRAIGHT_LINE_HANDLE, rem_p3 };
                } else {
                    splitCubic(rem_p0, rem_p1, rem_p2, rem_p3, local_t, &left, &right);
                }

                const prev_kind: StubBoundary = if (idx_in_curve == 0)
                    .continuation
                else
                    .{ .intersection = ts[idx_in_curve - 1].intersection_id };

                const stub_idx: u32 = @intCast(stubs.items.len);
                try stubs.append(.{
                    .points = left,
                    .is_straight = is_straight,
                    .prev_kind = prev_kind,
                    .next_kind = .{ .intersection = stop.intersection_id },
                    .curve_idx = c,
                });

                // Wire this stub as the INCOMING end of the joint at
                // stop.intersection_id. We're processing curve c, and the
                // intersection record's curve_a/curve_b tells us which side
                // of the joint this stub feeds into.
                const incoming_ends: *IntersectionEnds = &ends[stop.intersection_id];
                if (c == intersections.items[stop.intersection_id].curve_a) {
                    incoming_ends.incoming_a = stub_idx;
                } else {
                    incoming_ends.incoming_b = stub_idx;
                }

                rem_p0 = right[0];
                rem_p1 = right[1];
                rem_p2 = right[2];
                rem_p3 = right[3];
                prev_t = stop.t;
            }

            // Tail stub: from the last cut (or curve start) to t = 1.
            const tail_prev: StubBoundary = if (ts.len == 0)
                .continuation
            else
                .{ .intersection = ts[ts.len - 1].intersection_id };

            try stubs.append(.{
                .points = .{ rem_p0, rem_p1, rem_p2, rem_p3 },
                .is_straight = is_straight,
                .prev_kind = tail_prev,
                .next_kind = .continuation,
                .curve_idx = c,
            });
        }
    }

    // Second pass: every t-stop on curve c is also the START of the stub
    // immediately following it on the same curve — that's the "outgoing"
    // end at the joint.
    {
        var c: u32 = 0;
        while (c < num_curves) : (c += 1) {
            const ts = per_curve_ts[c].items;
            for (ts, 0..) |stop, idx_in_curve| {
                const out_stub: u32 = first_stub_of_curve[c] + @as(u32, @intCast(idx_in_curve)) + 1;
                const outgoing_ends: *IntersectionEnds = &ends[stop.intersection_id];
                if (c == intersections.items[stop.intersection_id].curve_a) {
                    outgoing_ends.outgoing_a = out_stub;
                } else {
                    outgoing_ends.outgoing_b = out_stub;
                }
            }
        }
    }

    // Snap the four endpoints meeting at each joint to their average so the
    // emitted sub-paths really do close up. Without this, the bisection's
    // sub-pixel error leaves a tiny gap at the crossing — fine visually but
    // breaks the "consecutive curves share an endpoint" invariant the rest
    // of the pipeline relies on.
    for (intersections.items, 0..) |_, idx| {
        const e = ends[idx];
        const sum_x = stubs.items[e.incoming_a].points[3].x +
            stubs.items[e.outgoing_a].points[0].x +
            stubs.items[e.incoming_b].points[3].x +
            stubs.items[e.outgoing_b].points[0].x;
        const sum_y = stubs.items[e.incoming_a].points[3].y +
            stubs.items[e.outgoing_a].points[0].y +
            stubs.items[e.incoming_b].points[3].y +
            stubs.items[e.outgoing_b].points[0].y;
        const snapped: types.Point = .{ .x = sum_x * 0.25, .y = sum_y * 0.25 };
        stubs.items[e.incoming_a].points[3] = snapped;
        stubs.items[e.outgoing_a].points[0] = snapped;
        stubs.items[e.incoming_b].points[3] = snapped;
        stubs.items[e.outgoing_b].points[0] = snapped;
    }

    // ---- step 3 + 4: walk stubs into closed sub-paths -------------------
    var first_stub_of_next_curve = try allocator.alloc(u32, num_curves);
    defer allocator.free(first_stub_of_next_curve);
    for (0..num_curves) |c| {
        const next_c = (c + 1) % num_curves;
        first_stub_of_next_curve[c] = first_stub_of_curve[next_c];
    }

    var visited = try allocator.alloc(bool, stubs.items.len);
    defer allocator.free(visited);
    @memset(visited, false);

    var result = std.ArrayList([]types.Point).init(allocator);
    errdefer {
        for (result.items) |p| allocator.free(p);
        result.deinit();
    }

    for (0..stubs.items.len) |start_idx| {
        if (visited[start_idx]) continue;

        var sub_path = std.ArrayList(types.Point).init(allocator);
        errdefer sub_path.deinit();

        var cur: u32 = @intCast(start_idx);
        while (!visited[cur]) {
            visited[cur] = true;
            const stub = stubs.items[cur];
            try sub_path.appendSlice(&stub.points);

            cur = switch (stub.next_kind) {
                .continuation => first_stub_of_next_curve[stub.curve_idx],
                .intersection => |id| blk: {
                    const e = ends[id];
                    // Seifert smoothing: leave the joint by switching to
                    // the OTHER curve's outgoing stub.
                    if (cur == e.incoming_a) break :blk e.outgoing_b;
                    if (cur == e.incoming_b) break :blk e.outgoing_a;
                    unreachable;
                },
            };
        }

        // Two-step transfer: once toOwnedSlice succeeds the buffer no longer
        // belongs to sub_path (so the errdefer above is a no-op), and if the
        // following result.append fails it would leak. Catching it with a
        // local errdefer keeps the OOM path tidy; on success the slice is
        // taken over by `result` and the outer errdefer cleans it up if a
        // later iteration fails.
        const owned = try sub_path.toOwnedSlice();
        errdefer allocator.free(owned);
        try result.append(owned);
    }

    return result.toOwnedSlice();
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
