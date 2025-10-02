const std = @import("std");
const images = @import("images.zig");
const shapes = @import("shapes/shapes.zig");
const texts = @import("texts/texts.zig");

pub const Asset = union(enum) {
    img: images.Image,
    shape: shapes.Shape,
    text: texts.Text,

    pub fn getBounds(self: Asset) [4]PointUV {
        return switch (self) {
            .img => |img| img.bounds,
            .shape => |shape| shape.bounds,
            .text => |text| text.bounds,
        };
    }

    pub fn getBoundsPtr(self: *Asset) *[4]PointUV {
        return switch (self.*) {
            .img => |*img| &img.bounds,
            .shape => |*shape| &shape.bounds,
            .text => |*text| &text.bounds,
        };
    }
};

pub const AssetSerialized = union(enum) {
    img: images.Serialized,
    shape: shapes.Serialized,
    text: texts.Serialized,
};

pub const Point = extern struct {
    x: f32,
    y: f32,

    pub fn mid(self: Point, other: Point) Point {
        return Point{
            .x = (self.x + other.x) * 0.5,
            .y = (self.y + other.y) * 0.5,
        };
    }

    pub fn angleTo(self: Point, other: anytype) f32 {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return std.math.atan2(dy, dx);
    }

    pub fn distance(self: Point, other: Point) f32 {
        return std.math.hypot(self.x - other.x, self.y - other.y);
    }

    pub fn diff(self: Point, other: Point) Point {
        return Point{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn length(self: Point) f32 {
        return std.math.hypot(self.x, self.y);
    }
};

pub const PointUV = extern struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,

    pub fn mid(self: PointUV, other: PointUV) Point {
        return Point{
            .x = (self.x + other.x) * 0.5,
            .y = (self.y + other.y) * 0.5,
        };
    }

    pub fn angleTo(self: PointUV, other: PointUV) f32 {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return std.math.atan2(dy, dx);
    }

    pub fn distance(self: PointUV, other: PointUV) f32 {
        return std.math.hypot(self.x - other.x, self.y - other.y);
    }

    pub fn toPoint(self: PointUV) Point {
        return Point{
            .x = self.x,
            .y = self.y,
        };
    }
};
