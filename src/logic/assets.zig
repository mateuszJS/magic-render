const std = @import("std");
const types = @import("types.zig");
const images = @import("images.zig");
const shapes = @import("shapes/shapes.zig");
const texts = @import("texts/texts.zig");
const utils = @import("utils.zig");
const snapshots = @import("snapshots.zig");
const asset_props = @import("asset_props.zig");
const typography_props = @import("texts/typography_props.zig");
const consts = @import("consts.zig");
const js_glue = @import("js_glue.zig");
const AssetId = @import("asset_id.zig").AssetId;

var assets: std.AutoArrayHashMap(u32, types.Asset) = undefined;
pub var selected_asset_id: AssetId = AssetId{};

pub fn init() void {
    assets = std.AutoArrayHashMap(u32, types.Asset).init(std.heap.page_allocator);
}

pub fn getIter() std.AutoArrayHashMap(u32, types.Asset).Iterator {
    return assets.iterator();
}

pub fn getSelectedAsset() ?*types.Asset {
    return assets.getPtr(selected_asset_id.getPrim());
}

pub fn hasSelectedAsset() bool {
    return assets.contains(selected_asset_id.getPrim());
}

pub fn getAsset(hovered_asset_id: AssetId) ?types.Asset {
    return assets.get(hovered_asset_id.getPrim());
}

pub fn getAssetPtr(hovered_asset_id: AssetId) ?*types.Asset {
    return assets.getPtr(hovered_asset_id.getPrim());
}

pub fn getSelectedImg() ?*images.Image {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => |*img| return img,
        .shape => return null,
        .text => return null,
    }
}

pub fn getSelectedShape() ?*shapes.Shape {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => |*shape| return shape,
        .text => return null,
    }
}

pub fn getSelectedText() ?*texts.Text {
    const asset = getSelectedAsset() orelse return null;
    switch (asset.*) {
        .img => return null,
        .shape => return null,
        .text => |*text| return text,
    }
}

pub fn addImage(id_or_zero: u32, points: [4]types.PointUV, texture_id: u32) !void {
    const id = if (id_or_zero == 0) utils.generateId() else id_or_zero;
    const asset = types.Asset{
        .img = images.Image.new(id, points, texture_id),
    };
    try assets.put(id, asset);
    snapshots.triggerNewSnapshot(true, true);
}

pub fn addShape(
    id_or_zero: u32,
    paths: []const []const types.Point,
    bounds: [4]types.PointUV,
    props: asset_props.Props,
    program_id: u32,
    program_inputs_id: u32,
    sdf_texture_id: u32,
    cache_texture_id: ?u32,
    padding: f32,
) !u32 {
    const id = if (id_or_zero == 0) utils.generateId() else id_or_zero;
    const shape = try shapes.Shape.new(
        id,
        paths,
        bounds,
        props,
        program_id,
        program_inputs_id,
        sdf_texture_id,
        cache_texture_id,
        padding,
        std.heap.page_allocator,
    );
    try assets.put(id, types.Asset{ .shape = shape });

    snapshots.triggerNewSnapshot(true, true);
    return id;
}

pub fn addText(
    id_or_zero: u32,
    content: []const u8,
    bounds: [4]types.PointUV,
    props: asset_props.Props,
    program_id: u32,
    program_inputs_id: u32,
    typo_props: typography_props.Serialized,
    sdf_texture_id: u32,
    is_sdf_shared: bool,
    padding: f32,
) !texts.Text {
    const id = if (id_or_zero == 0) utils.generateId() else id_or_zero;
    const text = try texts.Text.new(
        std.heap.page_allocator,
        id,
        content,
        bounds,
        props,
        program_id,
        program_inputs_id,
        typo_props,
        sdf_texture_id,
        is_sdf_shared,
        padding,
    );
    try assets.put(id, types.Asset{ .text = text });
    snapshots.triggerNewSnapshot(true, true);
    return text;
}

pub fn removeSelected() void {
    _ = assets.orderedRemove(selected_asset_id.getPrim());
}

pub fn createText(x: f32, y: f32, width: f32, font_size: f32, line_height: f32) !texts.Text {
    const bounds = [4]types.PointUV{
        .{ .x = x, .y = y, .u = 0.0, .v = 1.0 },
        .{ .x = x + width, .y = y, .u = 1.0, .v = 1.0 },
        .{ .x = x + width, .y = y - 1.0, .u = 1.0, .v = 0.0 },
        .{ .x = x, .y = y - 1.0, .u = 0.0, .v = 0.0 },
    };

    const typo_props = typography_props.Serialized{
        .font_size = font_size,
        .font_family_id = 0,
        .line_height = line_height,
    };

    return try addText(
        utils.generateId(),
        "Type here",
        bounds,
        asset_props.Props{},
        consts.SOLID_COLOR_PROGRAM_ID,
        consts.DEFAULT_INPUTS_ID,
        typo_props,
        js_glue.createSdfTexture(),
        false,
        consts.SKELETON_LINE_WIDTH * 0.5,
    );
}

pub fn createShape() !u32 {
    const props = asset_props.Props{
        .blur = null,
        // .blur = .{ .x = 30, .y = 30 },
    };

    const id = try addShape(
        0,
        &.{},
        consts.DEFAULT_BOUNDS,
        props,
        consts.SOLID_COLOR_PROGRAM_ID,
        consts.DEFAULT_INPUTS_ID,
        js_glue.createSdfTexture(),
        if (props.blur != null) js_glue.createCacheTexture() else null,
        consts.SKELETON_LINE_WIDTH * 0.5,
    );

    return id;
}

pub fn resetTo(snapshot_assets: []const types.AssetSerialized) !void {
    var iter = getIter();
    while (iter.next()) |entry| {
        switch (entry.value_ptr.*) {
            .img => {},
            .shape => |*shape| shape.deinit(),
            .text => |*text| text.deinit(),
        }
    }
    assets.clearAndFree();

    for (snapshot_assets) |asset| {
        switch (asset) {
            .img => |img| {
                try addImage(img.id, img.bounds, img.texture_id);
            },
            .shape => |shape| {
                _ = try addShape(
                    shape.id,
                    shape.paths,
                    shape.bounds,
                    shape.props,
                    shape.program_id,
                    shape.program_inputs_id,
                    shape.sdf_texture_id,
                    shape.cache_texture_id,
                    shape.padding,
                );
            },
            .text => |text| {
                _ = try addText(
                    text.id,
                    text.content orelse "", // should always be provided in real-life executions
                    text.bounds,
                    text.props,
                    text.program_id,
                    text.program_inputs_id,
                    text.typo_props,
                    text.sdf_texture_id,
                    text.is_sdf_shared,
                    text.padding,
                );
            },
        }
    }
}

pub fn clone(source_asset: types.Asset) !*types.Asset {
    const cloned_asset_id = switch (source_asset) {
        .img => |img| b: {
            const cloned_image = images.Image.new(utils.generateId(), img.bounds, img.texture_id);
            try assets.put(cloned_image.id, .{ .img = cloned_image });
            break :b cloned_image.id;
        },
        .shape => |shape| b: {
            const cloned_shape = try shape.clone();
            try assets.put(cloned_shape.id, .{ .shape = cloned_shape });
            break :b cloned_shape.id;
        },
        .text => |text| b: {
            const cloned_text = try text.clone();
            try assets.put(cloned_text.id, .{ .text = cloned_text });
            break :b cloned_text.id;
        },
    };

    selected_asset_id = AssetId{ ._prim = cloned_asset_id };
    return assets.getPtr(cloned_asset_id) orelse @panic("Just inserted shape alreayd does not exists??");
}
