const types = @import("types.zig");
const triangles = @import("triangles.zig");
const sdf_drawing = @import("sdf/drawing.zig");
const images = @import("images.zig");
const shapes = @import("shapes/shapes.zig");

// note: initializer of container-level variable must be comptime-known
// otherwise we coudl store everything in struct WebGpuProgramsInput = undefined
pub var draw_texture: *const fn ([]const types.PointUV, u32) void = undefined;
pub var draw_triangle: *const fn ([]const triangles.DrawInstance) void = undefined;
pub var compute_shape: *const fn ([]const types.Point, u32, u32, u32) void = undefined;
pub var start_combine_sdf: *const fn (u32, u32, u32, u32) void = undefined;
pub var combine_sdf: *const fn (u32, u32, u32, CombineSdfUniform, []const types.Point) void = undefined;
pub var finish_combine_sdf: *const fn () void = undefined;
pub var draw_blur: *const fn (u32, u32, u32, u32, f32, f32) void = undefined;
pub var draw_shape: *const fn ([]const types.PointUV, sdf_drawing.DrawUniform, u32, []const types.Point, []const f32) void = undefined;
pub var pick_texture: *const fn ([]const images.PickVertex, u32) void = undefined;
pub var pick_triangle: *const fn ([]const triangles.PickInstance) void = undefined;
pub var pick_shape: *const fn ([]const images.PickVertex, shapes.PickUniform, u32, []const types.Point, []const f32) void = undefined;

pub const CombineSdfUniform = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    initial_t: f32,
    padding: f32 = 0,
};

pub const WebGpuProgramsInput = struct {
    draw_texture: *const fn ([]const types.PointUV, u32) void,
    draw_triangle: *const fn ([]const triangles.DrawInstance) void,
    compute_shape: *const fn ([]const types.Point, u32, u32, u32) void,
    start_combine_sdf: *const fn (u32, u32, u32, u32) void,
    combine_sdf: *const fn (u32, u32, u32, CombineSdfUniform, []const types.Point) void,
    finish_combine_sdf: *const fn () void,
    draw_blur: *const fn (u32, u32, u32, u32, f32, f32) void,
    draw_shape: *const fn ([]const types.PointUV, sdf_drawing.DrawUniform, u32, []const types.Point, []const f32) void,
    pick_texture: *const fn ([]const images.PickVertex, u32) void,
    pick_triangle: *const fn ([]const triangles.PickInstance) void,
    pick_shape: *const fn ([]const images.PickVertex, shapes.PickUniform, u32, []const types.Point, []const f32) void,
};

pub fn connect(programs: *const WebGpuProgramsInput) void {
    // https://github.com/chung-leong/zigar/wiki/JavaScript-to-Zig-function-conversion

    draw_texture = programs.draw_texture;
    draw_triangle = programs.draw_triangle;
    compute_shape = programs.compute_shape;
    start_combine_sdf = programs.start_combine_sdf;
    combine_sdf = programs.combine_sdf;
    finish_combine_sdf = programs.finish_combine_sdf;
    draw_blur = programs.draw_blur;
    draw_shape = programs.draw_shape;
    pick_texture = programs.pick_texture;
    pick_triangle = programs.pick_triangle;
    pick_shape = programs.pick_shape;
}

pub fn deinit() void {
    draw_texture = undefined;
    draw_triangle = undefined;
    compute_shape = undefined;
    start_combine_sdf = undefined;
    combine_sdf = undefined;
    finish_combine_sdf = undefined;
    draw_blur = undefined;
    draw_shape = undefined;
    pick_texture = undefined;
    pick_triangle = undefined;
    pick_shape = undefined;
}
