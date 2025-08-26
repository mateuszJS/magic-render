const std = @import("std");

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

    pub fn clone(self: Point) Point {
        return Point{ .x = self.x, .y = self.y };
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
};

pub const TextureSize = struct {
    w: u32,
    h: u32,
};
