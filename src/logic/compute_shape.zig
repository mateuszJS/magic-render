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

pub fn computeShape(
    tex_id: u32,
    bounds: [4]types.PointUV,
    padding: f32,
    points: []types.Point,
    resize: f32,
) !sdf_drawing.SdfTex {
    const sdf_tex = sdf_drawing.getTexture(
        tex_id,
        bounds,
        padding,
        resize,
    );

    for (points) |*point| {
        point.x *= sdf_tex.scale;
        point.y *= sdf_tex.scale;

        point.x += consts.SDF_SAFE_PADDING + sdf_tex.padding;
        point.y += consts.SDF_SAFE_PADDING + sdf_tex.padding;
    }

    webgpu_glue.compute_shape(
        points,
        @intFromFloat(sdf_tex.size.w),
        @intFromFloat(sdf_tex.size.h),
        sdf_tex.id,
    );

    return sdf_tex;
}
