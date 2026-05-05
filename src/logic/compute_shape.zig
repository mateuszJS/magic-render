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

    // Force every path to wind clockwise BEFORE we scale into texel space. The
    // SDF fragment shader picks the fill side from the tangent's half-plane
    // (see ADRs/SDF rendering and drawShape/base.wgsl); mixing winding makes
    // some paths render as inverted holes. Doing it here — while paths are
    // still separate — means we never have to detect path boundaries inside a
    // flat buffer.
    ensureClockwiseOrientation(paths);

    // Now that every path is CW, walk the containment hierarchy and flip any
    // path whose nesting depth is odd back to CCW. That gives us "e", "o", "q"
    // style holes for free: outer contour stays a fill, the inner contour
    // becomes the opposite winding, and the shader's tangent test reports the
    // hole region as outside.
    fixHoleWinding(paths);

    // Flatten the paths into one contiguous buffer so the rest of the function
    // (scaling, arc-length sampling, the webgpu dispatch) can stay exactly the
    // way it was before paths became explicit.
    var total_len: usize = 0;
    for (paths) |path| total_len += path.len;
    const points = try std.heap.page_allocator.alloc(types.Point, total_len);
    {
        var offset: usize = 0;
        for (paths) |path| {
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
