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
    points: []types.Point,
    resize: f32,
) !sdf_drawing.SdfTex {
    var sdf_tex = sdf_drawing.getTexture(
        tex_id,
        bounds,
        padding,
        resize,
    );

    for (points, 0..) |*point, i| {
        if (path_utils.isStraightLineHandle(point.*)) {
            // NOTE: doesnt work
            if (i % 4 == 1) {
                point.x = points[i - 1].x;
                point.y = points[i - 1].y;
            } else if (i % 4 == 2) {
                // not sure if that case is even possible
                point.x = points[i + 1].x;
                point.y = points[i + 1].y;
            } else {
                @panic("Unexpected handle inde");
            }
        }

        point.x *= sdf_tex.scale;
        point.y *= sdf_tex.scale;

        point.x += consts.SDF_SAFE_PADDING + sdf_tex.padding;
        point.y += consts.SDF_SAFE_PADDING + sdf_tex.padding;
    }

    sdf_tex.points = points;

    webgpu_glue.compute_shape(
        points,
        @intFromFloat(sdf_tex.size.w),
        @intFromFloat(sdf_tex.size.h),
        sdf_tex.id,
    );

    return sdf_tex;
}
