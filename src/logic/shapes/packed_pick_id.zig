const std = @import("std");
const ASSET_ID_MIN = @import("../index.zig").ASSET_ID_MIN;

// --- Configuration ---
// Bit allocation for each integer
const BITS_ID1 = 14;
const BITS_ID2 = 9;
const BITS_ID3 = 9;

// Masks to help with decoding
const MASK_ID1 = (1 << BITS_ID1) - 1;
const MASK_ID2 = (1 << BITS_ID2) - 1;
const MASK_ID3 = (1 << BITS_ID3) - 1;

/// Encodes three integers into a single u32.
/// - id1: Must be in the range 1000 to 10000.
/// - id2: Must be in the range 0 to 511.
/// - id3: Must be in the range 0 to 511.
/// we allow quietly to fail if there will be bigger ranges
/// it's very unlikely with having that much point user wants to pick and modify individual points
pub fn encode(id1: u32, id2: u32, id3: u32) u32 {
    // Pack the values using bit-shifting and bitwise OR
    const val1_packed = id1 - ASSET_ID_MIN;
    const val2_packed = id2 << BITS_ID1;
    const val3_packed = id3 << (BITS_ID1 + BITS_ID2);

    return val1_packed | val2_packed | val3_packed;
}

pub const PointId = struct { shape: u32, path: u32, point: u32 };

/// Decodes a u32 back into three integers.
pub fn decode(encoded: u32) PointId {
    // Extract values using masks and bit-shifting
    const id1_raw = encoded & MASK_ID1;
    const id2 = (encoded >> BITS_ID1) & MASK_ID2;
    const id3 = (encoded >> (BITS_ID1 + BITS_ID2)) & MASK_ID3;

    return PointId{
        .shape = id1_raw + ASSET_ID_MIN, // Add the offset back
        .path = id2,
        .point = id3,
    };
}

// --- Test ---
test "encode and decode three integers in a u32" {
    const val1: u32 = 9999;
    const val2: u32 = 511;
    const val3: u32 = 123;

    const encoded = encode(val1, val2, val3);
    const decoded = decode(encoded);

    try std.testing.expectEqual(val1, decoded.id1);
    try std.testing.expectEqual(val2, decoded.id2);
    try std.testing.expectEqual(val3, decoded.id3);

    // Test with minimum values
    const val1_min: u32 = 1000;
    const val2_min: u32 = 0;
    const val3_min: u32 = 0;

    const encoded_min = encode(val1_min, val2_min, val3_min);
    const decoded_min = decode(encoded_min);

    try std.testing.expectEqual(val1_min, decoded_min.id1);
    try std.testing.expectEqual(val2_min, decoded_min.id2);
    try std.testing.expectEqual(val3_min, decoded_min.id3);
}
