const utils = @import("../utils.zig");

pub const Props = struct {
    font_size: f32,
    font_family_id: u32,
    line_height: f32,

    pub fn serialize(self: Props) Serialized {
        return Serialized{
            .font_size = self.font_size,
            .font_family_id = self.font_family_id,
            .line_height = self.line_height,
        };
    }
};

pub const Serialized = struct {
    font_size: f32,
    font_family_id: u32,
    line_height: f32,

    pub fn compare(self: Serialized, other: Serialized) bool {
        const all_match = utils.equalF32(self.font_size, other.font_size) and
            self.font_family_id == other.font_family_id and
            utils.equalF32(self.line_height, other.line_height);

        return all_match;
    }
};

pub fn deserialize(serialized: Serialized) Props {
    return Props{
        .font_size = serialized.font_size,
        .font_family_id = serialized.font_family_id,
        .line_height = serialized.line_height,
    };
}
