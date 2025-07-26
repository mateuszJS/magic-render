const Utils = @import("utils.zig");
const std = @import("std");
const Assets = @import("./assets.zig");

const EPSILON = std.math.floatEps(f32);

const SvgTexture = struct {
    id: u32,
    width: f32,
    height: f32,
};

var texture_max_size: f32 = 0.0;
var svg_textures: std.AutoHashMap(u32, SvgTexture) = undefined;
var increase_texture_size_cb: *const fn (u32, f32, f32) void = undefined;
var render_scale: f32 = 1.0;

pub fn init(max_size: f32, cb: *const fn (u32, f32, f32) void) void {
    svg_textures = std.AutoHashMap(u32, SvgTexture).init(std.heap.page_allocator);
    texture_max_size = max_size;
    increase_texture_size_cb = cb;
}

pub fn add_texture(texture_id: u32, width: f32, height: f32) void {
    const texture = SvgTexture{
        .id = texture_id,
        .width = width,
        .height = height,
    };
    svg_textures.put(texture_id, texture) catch unreachable;
}

fn resize_texture(texture_ptr: *SvgTexture, width: f32, height: f32) void {
    const new_width = @min(Utils.get_next_power_of_two(@max(texture_ptr.width, width / render_scale)), texture_max_size);
    const new_height = @min(Utils.get_next_power_of_two(@max(texture_ptr.height, height / render_scale)), texture_max_size);

    if (texture_ptr.width >= new_width - EPSILON and texture_ptr.height >= new_height - EPSILON) {
        return; // No resize needed
    }

    texture_ptr.*.width = new_width;
    texture_ptr.*.height = new_height;

    increase_texture_size_cb(texture_ptr.id, texture_ptr.width, texture_ptr.height);

    const has_reached_max_size = Utils.compare_floats(texture_ptr.width, texture_max_size) and Utils.compare_floats(texture_ptr.height, texture_max_size);

    if (has_reached_max_size) {
        _ = svg_textures.remove(texture_ptr.id);
    }
}

pub fn update_render_scale(scale: f32) void {
    render_scale = scale;

    var iterator = svg_textures.iterator();

    while (iterator.next()) |texture| {
        resize_texture(texture.value_ptr, texture.value_ptr.width, texture.value_ptr.height);
    }
}

pub fn ensure_svg_texture_quality(asset: Assets.Asset) void {
    const texture = svg_textures.getPtr(asset.texture_id) orelse return;

    const width = asset.points[0].distance(asset.points[1]) / render_scale;
    const height = asset.points[0].distance(asset.points[3]) / render_scale;

    resize_texture(texture, width, height);
}

// Test helper functions and variables
var test_callback_called: bool = false;
var test_callback_id: u32 = 0;
var test_callback_width: f32 = 0.0;
var test_callback_height: f32 = 0.0;

fn test_increase_texture_size_cb(id: u32, width: f32, height: f32) void {
    test_callback_called = true;
    test_callback_id = id;
    test_callback_width = width;
    test_callback_height = height;
}

fn reset_test_callback() void {
    test_callback_called = false;
    test_callback_id = 0;
    test_callback_width = 0.0;
    test_callback_height = 0.0;
}

test "resize_texture - simple update 60x60 to 100x100 should become 128x128" {
    // Setup
    svg_textures = std.AutoHashMap(u32, SvgTexture).init(std.testing.allocator);
    defer svg_textures.deinit();

    texture_max_size = 1000.0;
    render_scale = 1.0;
    increase_texture_size_cb = test_increase_texture_size_cb;
    reset_test_callback();

    // Create texture 60x60
    const texture = SvgTexture{ .id = 1, .width = 60.0, .height = 60.0 };
    try svg_textures.put(1, texture);

    const texture_ptr = svg_textures.getPtr(1).?;

    // Test: request 100x100
    resize_texture(texture_ptr, 100.0, 100.0);

    // Verify: should be 128x128 (next power of 2)
    try std.testing.expectEqual(128.0, texture_ptr.width);
    try std.testing.expectEqual(128.0, texture_ptr.height);

    // Verify callback was called
    try std.testing.expect(test_callback_called);
    try std.testing.expectEqual(1, test_callback_id);
    try std.testing.expectEqual(128.0, test_callback_width);
    try std.testing.expectEqual(128.0, test_callback_height);
}

test "resize_texture - 60x60 to 30x100 should become 64x128" {
    // Setup
    svg_textures = std.AutoHashMap(u32, SvgTexture).init(std.testing.allocator);
    defer svg_textures.deinit();

    texture_max_size = 1000.0;
    render_scale = 1.0;
    increase_texture_size_cb = test_increase_texture_size_cb;
    reset_test_callback();

    // Create texture 60x60
    const texture = SvgTexture{ .id = 2, .width = 60.0, .height = 60.0 };
    try svg_textures.put(2, texture);

    const texture_ptr = svg_textures.getPtr(2).?;

    // Test: request 30x100 (width smaller, height larger)
    resize_texture(texture_ptr, 30.0, 100.0);

    // Verify: should be 64x128 (max of current and requested, then next power of 2)
    try std.testing.expectEqual(64.0, texture_ptr.width);
    try std.testing.expectEqual(128.0, texture_ptr.height);

    // Verify callback was called
    try std.testing.expect(test_callback_called);
    try std.testing.expectEqual(2, test_callback_id);
    try std.testing.expectEqual(64.0, test_callback_width);
    try std.testing.expectEqual(128.0, test_callback_height);
}

test "resize_texture - 64x64 to 64x64 should stay 64x64 and no callback" {
    // Setup
    svg_textures = std.AutoHashMap(u32, SvgTexture).init(std.testing.allocator);
    defer svg_textures.deinit();

    texture_max_size = 1000.0;
    render_scale = 1.0;
    increase_texture_size_cb = test_increase_texture_size_cb;
    reset_test_callback();

    // Create texture 64x64 (already power of 2)
    const texture = SvgTexture{ .id = 3, .width = 64.0, .height = 64.0 };
    try svg_textures.put(3, texture);

    const texture_ptr = svg_textures.getPtr(3).?;

    // Test: request same size 64x64
    resize_texture(texture_ptr, 64.0, 64.0);

    // Verify: should stay 64x64
    try std.testing.expectEqual(64.0, texture_ptr.width);
    try std.testing.expectEqual(64.0, texture_ptr.height);

    // Verify callback was NOT called (no resize needed)
    try std.testing.expect(!test_callback_called);
}

test "resize_texture - texture removed when max size reached" {
    // Setup
    svg_textures = std.AutoHashMap(u32, SvgTexture).init(std.testing.allocator);
    defer svg_textures.deinit();

    texture_max_size = 128.0; // Set low max size
    render_scale = 1.0;
    increase_texture_size_cb = test_increase_texture_size_cb;
    reset_test_callback();

    // Create texture 60x60
    const texture = SvgTexture{ .id = 4, .width = 60.0, .height = 60.0 };
    try svg_textures.put(4, texture);

    const texture_ptr = svg_textures.getPtr(4).?;

    // Test: request 120x120 (will hit max size of 128x128)
    resize_texture(texture_ptr, 120.0, 120.0);

    // Verify callback was called with max size
    try std.testing.expect(test_callback_called);
    try std.testing.expectEqual(4, test_callback_id);
    try std.testing.expectEqual(128.0, test_callback_width);
    try std.testing.expectEqual(128.0, test_callback_height);

    // Verify texture was removed from collection
    try std.testing.expect(!svg_textures.contains(4));
}
