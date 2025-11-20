const utils = @import("../utils.zig");

pub const Props = struct {
    font_size: f32,
    is_sdf_shared: bool,
    line_height: f32,

    pub fn serialize(self: Props) Serialized {
        return Serialized{
            .font_size = self.font_size,
            .is_sdf_shared = self.is_sdf_shared,
            .line_height = self.line_height,
        };
    }
};

pub const Serialized = struct {
    font_size: f32,
    is_sdf_shared: bool,
    line_height: f32,

    pub fn compare(self: Serialized, other: Serialized) bool {
        const all_match = utils.equalF32(self.font_size, other.font_size) and
            self.is_sdf_shared == other.is_sdf_shared and
            utils.equalF32(self.line_height, other.line_height);

        return all_match;
    }
};

pub fn deserialize(serialized: Serialized) Props {
    return Props{
        .font_size = serialized.font_size,
        .is_sdf_shared = serialized.is_sdf_shared,
        .line_height = serialized.line_height,
    };
}
