const Point = @import("../types.zig").Point;
const std = @import("std");
const bounding_box = @import("bounding_box.zig");
const triangles = @import("../triangle.zig");
const squares = @import("../squares.zig");




pub fn get_shape_preview(shape: Shape) []triangles.DrawInstance {
    const allocator = std.heap.page_allocator;

    // Get the draw vertex data
    const vertex_data = try shape.get_draw_vertex_data(allocator);

    // Create a preview output
    const preview_output = VertexOutput{
        .curves = vertex_data.curves,
        .bounding_box = vertex_data.bounding_box,
        .uniform = vertex_data.uniform,
    };



    Triangle.get_draw_vertex_data()


    return preview_output;
}