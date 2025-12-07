// This file describes base properties shared among all the assets like opacity or blur

const std = @import("std");
const fill = @import("sdf/fill.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

pub const Props = struct {
    opacity: f32 = 1.0,
    blur: ?types.Point = null,

    pub fn compare(self: Props, other: Props) bool {
        if (!utils.equalF32(self.opacity, other.opacity)) {
            return false;
        }

        if (self.blur) |blur| {
            if (other.blur) |other_blur| {
                if (!utils.equalBoundPoint(blur, other_blur)) {
                    return false;
                }
            } else {
                return false;
            }
        } else if (other.blur != null) {
            return false;
        }

        return true;
    }
};
