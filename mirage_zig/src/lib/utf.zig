const std = @import("std");

pub const UtfError = error{
    InvalidUtf8,
    ScalarIndexOutOfBounds,
};

/// Counts the real number of characters in a UTF-8 byte slice.
/// It's useful when character occupies more than 1 byte, for example, for emojis.
pub fn countUnicodeLen(bytes: []const u8) UtfError!u64 {
    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;

    var count: u64 = 0;
    var index: usize = 0;
    while (index < bytes.len) {
        index += std.unicode.utf8ByteSequenceLength(bytes[index]) catch return error.InvalidUtf8;
        count += 1;
    }
    return count;
}

/// Returns the byte offset corresponding to the given character index in a UTF-8 byte slice.
/// For example, in the string "世界", the index 1 offset by 3 bytes
pub fn getByteOffsetForCharIndex(bytes: []const u8, scalar_index: u64) UtfError!usize {
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

const expectEqual = std.testing.expectEqual;

test "countUnicodeLen: counts the number of Unicode scalar values in a UTF-8 byte slice" {
    const s = "Hello, 世界!";
    const count = countUnicodeLen(s) catch unreachable;
    try expectEqual(10, count);
    try expectEqual(14, s.len);
}

test "getByteOffsetForCharIndex returns the byte offset for 1 byte characters" {
    const s = "Hello, 世界!";
    const offset = getByteOffsetForCharIndex(s, 7) catch unreachable;
    try expectEqual(7, offset);
}

test "getByteOffsetForCharIndex returns the byte offset for multi-byte characters" {
    const s = "Hello, 世界!";
    const offset = getByteOffsetForCharIndex(s, 8) catch unreachable;
    try expectEqual(10, offset);
}

test "getByteOffsetForCharIndex returns the byte offset for multi-byte characters (example)" {
    const s = "世界!";
    const offset = getByteOffsetForCharIndex(s, 1) catch unreachable;
    try expectEqual(3, offset);
}
