const std = @import("std");

pub const EncodingError = error{
    InvalidUpdate,
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error;

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

    pub fn writeVarU64(self: *Encoder, value: u64) !void {
        var rest = value;
        while (rest >= 0x80) {
            try self.writeByte(@as(u8, @intCast(rest & 0x7f)) | 0x80);
            rest >>= 7;
        }
        try self.writeByte(@intCast(rest));
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
        while (true) {
            const byte = try self.readByte();
            result |= (@as(u64, byte & 0x7f) << shift);
            if ((byte & 0x80) == 0) return result;
            if (shift >= 63) return error.VarIntOverflow;
            shift += 7;
        }
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
