const std = @import("std");

pub const AssetId = struct {
    // 0 -> no asset/element selected
    _prim: u32 = 0, // primary
    _sec: u32 = 0, // secondary, represets indicies, value is always 1 bigger than should be, so 0 can represent no index
    _tert: u32 = 0, // tertiary, represets indicies, value is always 1 bigger than should be, so 0 can represent no index
    _quat: u32 = 0, // quaternary, not used yet

    pub fn isPrim(self: AssetId) bool {
        return self._prim != 0;
    }

    pub fn getPrim(self: AssetId) u32 {
        return self._prim; // it's just to maintain consistency with otehr fields
    }

    pub fn isSec(self: AssetId) bool {
        return self._sec != 0;
    }

    // make sure secondary is valid before calling this method
    pub fn getSec(self: AssetId) u32 {
        return self._sec - 1;
    }

    pub fn setSec(self: *AssetId, value: u32) void {
        self._sec = value + 1;
    }

    pub fn isTert(self: AssetId) bool {
        return self._tert != 0;
    }

    // make sure tertiary is valid before calling this method
    pub fn getTert(self: AssetId) u32 {
        return self._tert - 1;
    }

    pub fn fromArray(values: [4]u32) AssetId {
        return AssetId{
            ._prim = values[0],
            ._sec = values[1],
            ._tert = values[2],
            ._quat = values[3],
        };
    }

    pub fn serialize(self: AssetId) [4]u32 {
        return [_]u32{ self._prim, self._sec, self._tert, self._quat };
    }

    pub fn format(
        self: AssetId,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{d}, {d}, {d}, {d}", .{ self._prim, self._sec, self._tert, self._quat });
    }
};
