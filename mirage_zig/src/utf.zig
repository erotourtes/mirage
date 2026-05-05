const std = @import("std");

pub const UtfError = error{
    InvalidUtf8,
    ScalarIndexOutOfBounds,
};

pub fn scalarCount(bytes: []const u8) UtfError!u64 {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;

    var count: u64 = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        index += std.unicode.utf8ByteSequenceLength(bytes[index]) catch return error.InvalidUtf8;
        count += 1;
    }
    return count;
}

pub fn byteOffsetForScalarIndex(bytes: []const u8, scalar_index: u64) UtfError!usize {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;

    var count: u64 = 0;
    var index: usize = 0;
    while (index < bytes.len and count < scalar_index) {
        index += std.unicode.utf8ByteSequenceLength(bytes[index]) catch return error.InvalidUtf8;
        count += 1;
    }
    if (count != scalar_index) return error.ScalarIndexOutOfBounds;
    return index;
}
