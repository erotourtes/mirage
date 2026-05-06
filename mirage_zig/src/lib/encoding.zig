const std = @import("std");

pub const EncodingError = error{
    InvalidUpdate,
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error;

const varint_data_bits_per_byte = 7;
const varint_continuation_bit: u8 = 0b1000_0000;
const varint_data_mask: u8 = 0b0111_1111;
const varint_single_byte_limit: u64 = 1 << varint_data_bits_per_byte;

pub const Encoder = struct {
    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Encoder) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn writeByte(self: *Encoder, byte: u8) !void {
        try self.bytes.append(self.allocator, byte);
    }

    /// Writes a u64 as a variable-length integer using the LEB128 encoding.
    ///
    /// It encodes the integer in 7-bit groups,
    /// with the most significant bit of each byte indicating
    /// if there are more bytes to read.
    pub fn writeVarU64(self: *Encoder, value: u64) !void {
        var rest = value;
        while (rest >= varint_single_byte_limit) : (rest >>= varint_data_bits_per_byte) {
            const data_bits: u8 = @intCast(rest & varint_data_mask);
            try self.writeByte(data_bits | varint_continuation_bit);
        }
        const bits: u8 = @intCast(rest);
        try self.writeByte(bits);
    }

    pub fn writeBytes(self: *Encoder, value: []const u8) !void {
        try self.writeVarU64(value.len);
        try self.bytes.appendSlice(self.allocator, value);
    }

    pub fn toOwnedSlice(self: *Encoder) ![]u8 {
        return try self.bytes.toOwnedSlice(self.allocator);
    }
};

pub const Decoder = struct {
    bytes: []const u8,
    index: usize = 0,

    pub fn init(bytes: []const u8) Decoder {
        return .{ .bytes = bytes };
    }

    pub fn readByte(self: *Decoder) EncodingError!u8 {
        if (self.index >= self.bytes.len) return error.InvalidUpdate;
        const byte = self.bytes[self.index];
        self.index += 1;
        return byte;
    }

    pub fn readVarU64(self: *Decoder) EncodingError!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        var i: u8 = 0;
        while (i < 10) : (i += 1) {
            const byte = try self.readByte();
            const payload = @as(u64, byte & varint_data_mask);
            if (i == 9 and payload > 1) return error.VarIntOverflow;
            result |= payload << shift;
            if ((byte & varint_continuation_bit) == 0) return result;
            if (i == 9) return error.VarIntOverflow;
            shift += varint_data_bits_per_byte;
        }

        unreachable;
    }

    pub fn readBytes(self: *Decoder) EncodingError![]const u8 {
        const len = try self.readVarU64();
        if (len > std.math.maxInt(usize)) return error.InvalidUpdate;
        return try self.readRaw(@intCast(len));
    }

    pub fn readRaw(self: *Decoder, len: usize) EncodingError![]const u8 {
        const end = self.index + @as(usize, @intCast(len));
        if (end < self.index or end > self.bytes.len) return error.InvalidUpdate;
        const value = self.bytes[self.index..end];
        self.index = end;
        return value;
    }

    pub fn expectEnd(self: Decoder) EncodingError!void {
        if (self.index != self.bytes.len) return error.TrailingBytes;
    }
};

test "encoding: 127" {
    const allocator = std.testing.allocator;
    var enc = Encoder.init(allocator);
    errdefer enc.deinit();

    try enc.writeVarU64(127);
    const bytes = try enc.toOwnedSlice();
    defer allocator.free(bytes);

    try std.testing.expectEqual(1, bytes.len);
    try std.testing.expectEqual(0b01111111, bytes[0]);
}

test "encoding: 128" {
    const allocator = std.testing.allocator;
    var enc = Encoder.init(allocator);
    errdefer enc.deinit();

    try enc.writeVarU64(128);
    const bytes = try enc.toOwnedSlice();
    defer allocator.free(bytes);

    try std.testing.expectEqual(2, bytes.len);
    try std.testing.expectEqual(0b10000000, bytes[0]);
    try std.testing.expectEqual(0b00000001, bytes[1]);
}

test "encoding: max u64 value" {
    const allocator = std.testing.allocator;
    var enc = Encoder.init(allocator);
    errdefer enc.deinit();

    try enc.writeVarU64(0xFFFF_FFFF_FFFF_FFFF);
    const bytes = try enc.toOwnedSlice();
    defer allocator.free(bytes);

    try std.testing.expectEqual(10, bytes.len);
    try std.testing.expectEqual(0b11111111, bytes[0]);
    try std.testing.expectEqual(0b11111111, bytes[1]);
    try std.testing.expectEqual(0b11111111, bytes[2]);
    try std.testing.expectEqual(0b11111111, bytes[3]);
    try std.testing.expectEqual(0b11111111, bytes[4]);
    try std.testing.expectEqual(0b11111111, bytes[5]);
    try std.testing.expectEqual(0b11111111, bytes[6]);
    try std.testing.expectEqual(0b11111111, bytes[7]);
    try std.testing.expectEqual(0b11111111, bytes[8]);
    try std.testing.expectEqual(0b00000001, bytes[9]);
}

test "decoding: 127" {
    const bytes = &.{0b01111111};
    var dec = Decoder.init(bytes);
    const value = try dec.readVarU64();
    try std.testing.expectEqual(127, value);
}

test "decoding: 128" {
    const bytes = &.{ 0b10000000, 0b00000001 };
    var dec = Decoder.init(bytes);
    const value = try dec.readVarU64();
    try std.testing.expectEqual(128, value);
}

test "decoding: max u64 value" {
    const bytes = &.{
        0b11111111, 0b11111111, 0b11111111, 0b11111111, 0b11111111,
        0b11111111, 0b11111111, 0b11111111, 0b11111111, 0b00000001,
    };
    var dec = Decoder.init(bytes);
    const value = try dec.readVarU64();
    try std.testing.expectEqual(0xFFFF_FFFF_FFFF_FFFF, value);
}
