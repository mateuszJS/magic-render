const types = @import("types.zig");
const sdf_drawing = @import("sdf/drawing.zig");
const fonts = @import("texts/fonts.zig");
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
    points: []types.Point, // it has to be a safe copy allocated with on a heap
    resize: f32,
) !sdf_drawing.SdfTex {
    var sdf_tex = sdf_drawing.getTexture(
        tex_id,
        bounds,
        padding,
        resize,
    );

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
