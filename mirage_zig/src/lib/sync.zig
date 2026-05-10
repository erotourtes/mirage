const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const store_mod = @import("store.zig");
const encoding = @import("encoding.zig");
const utf = @import("utf.zig");
const attrs = @import("attrs.zig");

pub const update_magic = "MYPEACE";
pub const update_version: u8 = 1;

const ContentTag = enum(u8) {
    string = 1,
    format = 2,
};

const ByteColumnCodec = enum(u8) {
    raw = 0,
    rle = 1,
};

const OriginKind = enum(u8) {
    null = 0,
    same_client_previous_clock = 1,
    same_client_clock = 2,
    full_id = 3,
};

pub const Error = error{
    InvalidUtf8,
    ScalarIndexOutOfBounds,
    InvalidUpdate,
    UnsupportedUpdateVersion,
    TextTooLarge,
    UnsupportedContent,
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error || store_mod.StoreError;

pub const ReadUpdateError = Error || error{
    IndexOutOfBounds,
    InvalidHandle,
    ItemTooLarge,
    MissingDependency,
    PendingUpdatesTooLarge,
};

pub const StateVector = std.array_hash_map.Auto(id.ClientId, id.Clock);

pub const EncodeView = struct {
    allocator: std.mem.Allocator,
    store: *const store_mod.StructStore,
    items: []const item_mod.Item,
    bytes: []const u8,
};

pub const DecodedItem = struct {
    id: id.Id,
    len: id.Clock,
    initial_left_origin_id: ?id.Id,
    initial_right_origin_id: ?id.Id,
    content: DecodedContent,
};

pub const DecodedContent = union(enum) {
    string: []const u8,
    format: DecodedFormat,
};

pub const DecodedFormat = struct {
    key: []const u8,
    value: attrs.AttributeValue,
};

pub const DecodedDeleteRange = struct {
    client: id.ClientId,
    clock: id.Clock,
    len: id.Clock,
};

pub fn ReadUpdateCallbacks(comptime Context: type) type {
    return struct {
        context: Context,
        item: *const fn (context: Context, decoded: DecodedItem) ReadUpdateError!void,
        deletedRange: *const fn (context: Context, decoded: DecodedDeleteRange) ReadUpdateError!void,
    };
}

pub fn encodeStateVector(view: EncodeView, allocator: std.mem.Allocator) Error![]u8 {
    var enc = encoding.Encoder.init(allocator);
    errdefer enc.deinit();

    try enc.writeVarU64(view.store.clients.count());
    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        if (client_structs.items.items.len == 0) continue;
        try enc.writeVarU64(client);
        try enc.writeVarU64(view.store.getState(view.items, client));
    }
    return try enc.toOwnedSlice();
}

pub fn encodeStateAsUpdate(
    view: EncodeView,
    allocator: std.mem.Allocator,
    encoded_target_state_vector: ?[]const u8,
) Error![]u8 {
    var target_state = try decodeStateVector(view.allocator, encoded_target_state_vector orelse &.{});
    defer target_state.deinit(view.allocator);

    var enc = encoding.Encoder.init(allocator);
    errdefer enc.deinit();

    try enc.bytes.appendSlice(allocator, update_magic);
    try enc.writeByte(update_version);
    try writeStructs(view, &enc, &target_state);
    try writeDeleteSet(view, &enc);
    return try enc.toOwnedSlice();
}

pub fn decodeStateVector(allocator: std.mem.Allocator, encoded: []const u8) Error!StateVector {
    var state: StateVector = .empty;
    errdefer state.deinit(allocator);

    if (encoded.len == 0) return state;

    var dec = encoding.Decoder.init(encoded);
    const count = try dec.readVarU64();
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const client = try dec.readVarU64();
        const clock = try dec.readVarU64();
        try state.put(allocator, client, clock);
    }
    try dec.expectEnd();
    return state;
}

fn writeId(enc: *encoding.Encoder, value: id.Id) Error!void {
    try enc.writeVarU64(value.client);
    try enc.writeVarU64(value.clock);
}

fn readId(dec: *encoding.Decoder) Error!id.Id {
    return .{
        .client = try dec.readVarU64(),
        .clock = try dec.readVarU64(),
    };
}

pub fn readUpdate(comptime Context: type, update: []const u8, callbacks: ReadUpdateCallbacks(Context)) ReadUpdateError!void {
    var dec = encoding.Decoder.init(update);
    const magic = try dec.readRaw(update_magic.len);
    if (!std.mem.eql(u8, magic, update_magic)) return error.InvalidUpdate;
    const version = try dec.readByte();
    if (version != update_version) return error.UnsupportedUpdateVersion;

    const client_count = try dec.readVarU64();
    var client_index: usize = 0;
    while (client_index < client_count) : (client_index += 1) {
        const client = try dec.readVarU64();
        try readClientBlock(Context, &dec, callbacks, client);
    }

    const delete_client_count = try dec.readVarU64();
    var delete_client_index: usize = 0;
    while (delete_client_index < delete_client_count) : (delete_client_index += 1) {
        const client = try dec.readVarU64();
        const delete_count = try dec.readVarU64();
        var delete_index: usize = 0;
        while (delete_index < delete_count) : (delete_index += 1) {
            const clock = try dec.readVarU64();
            const delete_len = try dec.readVarU64();
            try callbacks.deletedRange(callbacks.context, .{
                .client = client,
                .clock = clock,
                .len = delete_len,
            });
        }
    }
    try dec.expectEnd();
}

fn readClientBlock(
    comptime Context: type,
    dec: *encoding.Decoder,
    callbacks: ReadUpdateCallbacks(Context),
    client: id.ClientId,
) ReadUpdateError!void {
    const item_count_u64 = try dec.readVarU64();
    if (item_count_u64 > std.math.maxInt(usize)) return error.InvalidUpdate;
    const item_count: usize = @intCast(item_count_u64);
    if (item_count == 0) return error.InvalidUpdate;

    var clock = try dec.readVarU64();

    var lens_dec = try readVarU64Column(dec);
    var left_origin_kinds = try readByteColumn(dec);
    var right_origin_kinds = try readByteColumn(dec);
    var left_origin_dec = encoding.Decoder.init(try dec.readBytes());
    var right_origin_dec = encoding.Decoder.init(try dec.readBytes());
    var content_tags = try readByteColumn(dec);

    var string_lens_dec = try readVarU64Column(dec);
    const string_bytes = try dec.readBytes();
    var string_byte_offset: usize = 0;

    var format_key_lens_dec = try readVarU64Column(dec);
    const format_key_bytes = try dec.readBytes();
    var format_key_offset: usize = 0;
    var format_value_nulls = try readByteColumn(dec);
    var format_value_lens_dec = try readVarU64Column(dec);
    const format_value_bytes = try dec.readBytes();
    var format_value_offset: usize = 0;

    for (0..item_count) |_| {
        const len_value = try lens_dec.read();
        if (len_value == 0) return error.InvalidUpdate;

        const left_origin = try readOrigin(&left_origin_kinds, &left_origin_dec, client, clock);
        const right_origin = try readOrigin(&right_origin_kinds, &right_origin_dec, client, clock);

        const content_tag = std.enums.fromInt(ContentTag, try content_tags.read()) orelse
            return error.UnsupportedContent;
        const content: DecodedContent = switch (content_tag) {
            .string => blk: {
                const byte_len = try readColumnLen(&string_lens_dec);
                if (string_byte_offset + byte_len > string_bytes.len) return error.InvalidUpdate;
                const bytes = string_bytes[string_byte_offset..][0..byte_len];
                string_byte_offset += byte_len;

                const logical_len = try utf.countUnicodeLen(bytes);
                if (logical_len != len_value) return error.InvalidUpdate;
                break :blk .{ .string = bytes };
            },
            .format => blk: {
                if (len_value != 1) return error.InvalidUpdate;

                const key_len = try readColumnLen(&format_key_lens_dec);
                if (format_key_offset + key_len > format_key_bytes.len) return error.InvalidUpdate;
                const key = format_key_bytes[format_key_offset..][0..key_len];
                format_key_offset += key_len;

                const value_is_null = (try format_value_nulls.read()) != 0;

                const value: attrs.AttributeValue = if (value_is_null)
                    .null
                else value: {
                    const value_len = try readColumnLen(&format_value_lens_dec);
                    if (format_value_offset + value_len > format_value_bytes.len) return error.InvalidUpdate;
                    const value_bytes = format_value_bytes[format_value_offset..][0..value_len];
                    format_value_offset += value_len;
                    break :value .{ .string = value_bytes };
                };
                break :blk .{ .format = .{ .key = key, .value = value } };
            },
        };

        try callbacks.item(callbacks.context, .{
            .id = .{ .client = client, .clock = clock },
            .len = len_value,
            .initial_left_origin_id = left_origin,
            .initial_right_origin_id = right_origin,
            .content = content,
        });
        clock += len_value;
    }

    try lens_dec.expectEnd();
    try left_origin_kinds.expectEnd();
    try right_origin_kinds.expectEnd();
    try left_origin_dec.expectEnd();
    try right_origin_dec.expectEnd();
    try content_tags.expectEnd();
    try string_lens_dec.expectEnd();
    if (string_byte_offset != string_bytes.len) return error.InvalidUpdate;
    try format_key_lens_dec.expectEnd();
    if (format_key_offset != format_key_bytes.len) return error.InvalidUpdate;
    try format_value_nulls.expectEnd();
    try format_value_lens_dec.expectEnd();
    if (format_value_offset != format_value_bytes.len) return error.InvalidUpdate;
}

const ByteColumnDecoder = struct {
    codec: u8,
    raw: []const u8,
    raw_index: usize = 0,
    rle_dec: encoding.Decoder,
    run_value: u8 = 0,
    run_remaining: u64 = 0,

    fn read(self: *ByteColumnDecoder) Error!u8 {
        const codec = std.enums.fromInt(ByteColumnCodec, self.codec) orelse
            return error.InvalidUpdate;
        return switch (codec) {
            .raw => blk: {
                if (self.raw_index >= self.raw.len) return error.InvalidUpdate;
                const value = self.raw[self.raw_index];
                self.raw_index += 1;
                break :blk value;
            },
            .rle => blk: {
                if (self.run_remaining == 0) {
                    self.run_remaining = try self.rle_dec.readVarU64();
                    if (self.run_remaining == 0) return error.InvalidUpdate;
                    self.run_value = try self.rle_dec.readByte();
                }
                self.run_remaining -= 1;
                break :blk self.run_value;
            },
        };
    }

    fn expectEnd(self: *ByteColumnDecoder) Error!void {
        const codec = std.enums.fromInt(ByteColumnCodec, self.codec) orelse
            return error.InvalidUpdate;
        switch (codec) {
            .raw => if (self.raw_index != self.raw.len) return error.InvalidUpdate,
            .rle => {
                if (self.run_remaining != 0) return error.InvalidUpdate;
                try self.rle_dec.expectEnd();
            },
        }
    }
};

fn readByteColumn(dec: *encoding.Decoder) Error!ByteColumnDecoder {
    const codec = try dec.readByte();
    const payload = try dec.readBytes();
    return .{
        .codec = codec,
        .raw = payload,
        .rle_dec = encoding.Decoder.init(payload),
    };
}

const VarU64ColumnDecoder = struct {
    codec: u8,
    raw_dec: encoding.Decoder,
    rle_dec: encoding.Decoder,
    run_value: u64 = 0,
    run_remaining: u64 = 0,

    fn read(self: *VarU64ColumnDecoder) Error!u64 {
        const codec = std.enums.fromInt(ByteColumnCodec, self.codec) orelse
            return error.InvalidUpdate;
        return switch (codec) {
            .raw => try self.raw_dec.readVarU64(),
            .rle => blk: {
                if (self.run_remaining == 0) {
                    self.run_remaining = try self.rle_dec.readVarU64();
                    if (self.run_remaining == 0) return error.InvalidUpdate;
                    self.run_value = try self.rle_dec.readVarU64();
                }
                self.run_remaining -= 1;
                break :blk self.run_value;
            },
        };
    }

    fn expectEnd(self: *VarU64ColumnDecoder) Error!void {
        const codec = std.enums.fromInt(ByteColumnCodec, self.codec) orelse
            return error.InvalidUpdate;
        switch (codec) {
            .raw => try self.raw_dec.expectEnd(),
            .rle => {
                if (self.run_remaining != 0) return error.InvalidUpdate;
                try self.rle_dec.expectEnd();
            },
        }
    }
};

fn readVarU64Column(dec: *encoding.Decoder) Error!VarU64ColumnDecoder {
    const codec = try dec.readByte();
    const payload = try dec.readBytes();
    return .{
        .codec = codec,
        .raw_dec = encoding.Decoder.init(payload),
        .rle_dec = encoding.Decoder.init(payload),
    };
}

fn readOrigin(
    kinds: *ByteColumnDecoder,
    values: *encoding.Decoder,
    client: id.ClientId,
    clock: id.Clock,
) Error!?id.Id {
    const kind = std.enums.fromInt(OriginKind, try kinds.read()) orelse
        return error.InvalidUpdate;
    return switch (kind) {
        .null => null,
        .same_client_previous_clock => if (clock == 0)
            error.InvalidUpdate
        else
            .{ .client = client, .clock = clock - 1 },
        .same_client_clock => .{ .client = client, .clock = try values.readVarU64() },
        .full_id => try readId(values),
    };
}

fn readColumnLen(dec: *VarU64ColumnDecoder) Error!usize {
    const len = try dec.read();
    if (len > std.math.maxInt(usize)) return error.InvalidUpdate;
    return @intCast(len);
}

fn writeStructs(view: EncodeView, enc: *encoding.Encoder, target_state: *const StateVector) Error!void {
    var changed_clients: usize = 0;
    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        const structs = client_structs.items.items;
        if (structs.len == 0) continue;

        const target_clock = target_state.get(client) orelse 0;
        const last_handle = structs[structs.len - 1];
        const last = view.items[last_handle];
        if (last.id.clock + last.getClockLen() > target_clock) {
            changed_clients += 1;
        }
    }

    try enc.writeVarU64(changed_clients);
    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        const target_clock = target_state.get(client) orelse 0;
        const first_index = firstStructAfterClock(view.items, client_structs.items.items, target_clock)
            // skip clients that have no changes
            orelse continue;
        const changed_items = client_structs.items.items[first_index..];

        try enc.writeVarU64(client);
        try enc.writeVarU64(changed_items.len);
        try writeClientColumns(view, enc, target_clock, changed_items);
    }
}

fn writeClientColumns(
    view: EncodeView,
    enc: *encoding.Encoder,
    target_clock: id.Clock,
    changed_items: []const item_mod.ItemHandle,
) Error!void {
    const first = view.items[changed_items[0]];
    const first_clock = brk: {
        std.debug.assert(first.id.clock <= target_clock);
        std.debug.assert(target_clock < first.id.clock + first.getClockLen());
        break :brk target_clock;
    };
    try enc.writeVarU64(first_clock);

    // Clock len of written item
    var lens: std.ArrayList(u64) = .empty;
    defer lens.deinit(view.allocator);
    var left_origin_kinds: std.ArrayList(u8) = .empty;
    defer left_origin_kinds.deinit(view.allocator);
    var right_origin_kinds: std.ArrayList(u8) = .empty;
    defer right_origin_kinds.deinit(view.allocator);
    var left_origins = encoding.Encoder.init(view.allocator);
    defer left_origins.deinit();
    var right_origins = encoding.Encoder.init(view.allocator);
    defer right_origins.deinit();
    var content_tags: std.ArrayList(u8) = .empty;
    defer content_tags.deinit(view.allocator);
    var string_lens: std.ArrayList(u64) = .empty;
    defer string_lens.deinit(view.allocator);
    var string_bytes: std.ArrayList(u8) = .empty;
    defer string_bytes.deinit(view.allocator);
    var format_key_lens: std.ArrayList(u64) = .empty;
    defer format_key_lens.deinit(view.allocator);
    var format_key_bytes: std.ArrayList(u8) = .empty;
    defer format_key_bytes.deinit(view.allocator);
    var format_value_nulls: std.ArrayList(u8) = .empty;
    defer format_value_nulls.deinit(view.allocator);
    var format_value_lens: std.ArrayList(u64) = .empty;
    defer format_value_lens.deinit(view.allocator);
    var format_value_bytes: std.ArrayList(u8) = .empty;
    defer format_value_bytes.deinit(view.allocator);

    for (changed_items) |handle| {
        const current = view.items[handle];
        const current_len = current.getClockLen();
        const is_target_starts_inside_current = target_clock > current.id.clock;
        const offset = if (is_target_starts_inside_current) target_clock - current.id.clock else 0;
        const write_clock = current.id.clock + offset;
        const write_len = current_len - offset;
        try lens.append(view.allocator, write_len);

        const left_origin: ?id.Id = if (is_target_starts_inside_current)
            .{ .client = current.id.client, .clock = write_clock - 1 }
        else
            current.initial_left_origin_id;
        try writeOrigin(view.allocator, &left_origin_kinds, &left_origins, current.id.client, write_clock, left_origin);
        // TODO: reverse origins?
        try writeOrigin(view.allocator, &right_origin_kinds, &right_origins, current.id.client, write_clock, current.initial_right_origin_id);

        switch (current.content) {
            .string => |slice| {
                const kind: u8 = @intFromEnum(ContentTag.string);
                try content_tags.append(view.allocator, kind);
                const item_bytes = sliceBytes(view, slice);
                const byte_offset = try utf.getByteOffsetForCharIndex(item_bytes, offset);
                const bytes = item_bytes[byte_offset..];
                try string_lens.append(view.allocator, bytes.len);
                try string_bytes.appendSlice(view.allocator, bytes);
            },
            .format => |format_slice| {
                // format items are 1 clock long. they can't be partially included
                if (offset != 0) return error.InvalidUpdate;
                const kind: u8 = @intFromEnum(ContentTag.format);
                try content_tags.append(view.allocator, kind);

                const key = attributeKeyBytes(view, format_slice);
                try format_key_lens.append(view.allocator, key.len);
                try format_key_bytes.appendSlice(view.allocator, key);
                try format_value_nulls.append(view.allocator, if (format_slice.value_is_null) 1 else 0);
                if (!format_slice.value_is_null) {
                    const value = attributeValueBytes(view, format_slice);
                    try format_value_lens.append(view.allocator, value.len);
                    try format_value_bytes.appendSlice(view.allocator, value);
                }
            },
        }
    }

    try writeVarU64Column(enc, view.allocator, lens.items);
    try writeByteColumn(enc, view.allocator, left_origin_kinds.items);
    try writeByteColumn(enc, view.allocator, right_origin_kinds.items);
    try enc.writeBytes(left_origins.bytes.items);
    try enc.writeBytes(right_origins.bytes.items);
    try writeByteColumn(enc, view.allocator, content_tags.items);
    try writeVarU64Column(enc, view.allocator, string_lens.items);
    try enc.writeBytes(string_bytes.items);
    try writeVarU64Column(enc, view.allocator, format_key_lens.items);
    try enc.writeBytes(format_key_bytes.items);
    try writeByteColumn(enc, view.allocator, format_value_nulls.items);
    try writeVarU64Column(enc, view.allocator, format_value_lens.items);
    try enc.writeBytes(format_value_bytes.items);
}

/// Decides if it's better to use RLE or raw encoding
fn writeByteColumn(enc: *encoding.Encoder, allocator: std.mem.Allocator, bytes: []const u8) Error!void {
    var rle = encoding.Encoder.init(allocator);
    defer rle.deinit();
    var index: usize = 0;
    while (index < bytes.len) {
        const value = bytes[index];
        var run_len: u64 = 1;
        index += 1;
        while (index < bytes.len and bytes[index] == value) : (index += 1) {
            run_len += 1;
        }
        try rle.writeVarU64(run_len);
        try rle.writeByte(value);
    }

    const use_rle = rle.bytes.items.len < bytes.len;
    const codec: u8 = @intFromEnum(if (use_rle) ByteColumnCodec.rle else ByteColumnCodec.raw);
    try enc.writeByte(codec);
    try enc.writeBytes(if (use_rle) rle.bytes.items else bytes);
}

fn writeVarU64Column(enc: *encoding.Encoder, allocator: std.mem.Allocator, values: []const u64) Error!void {
    var raw = encoding.Encoder.init(allocator);
    defer raw.deinit();
    for (values) |value| {
        try raw.writeVarU64(value);
    }

    var rle = encoding.Encoder.init(allocator);
    defer rle.deinit();
    var index: usize = 0;
    while (index < values.len) {
        const value = values[index];
        var run_len: u64 = 1;
        index += 1;
        while (index < values.len and values[index] == value) : (index += 1) {
            run_len += 1;
        }
        try rle.writeVarU64(run_len);
        try rle.writeVarU64(value);
    }

    const use_rle = rle.bytes.items.len < raw.bytes.items.len;
    const codec: u8 = @intFromEnum(if (use_rle) ByteColumnCodec.rle else ByteColumnCodec.raw);
    try enc.writeByte(codec);
    try enc.writeBytes(if (use_rle) rle.bytes.items else raw.bytes.items);
}

test "VarU64 column uses RLE when repeated values are smaller" {
    const allocator = std.testing.allocator;
    const values = [_]u64{ 1, 1, 1, 1, 1 };

    var enc = encoding.Encoder.init(allocator);
    defer enc.deinit();
    try writeVarU64Column(&enc, allocator, &values);
    try std.testing.expectEqual(@as(u8, @intFromEnum(ByteColumnCodec.rle)), enc.bytes.items[0]);

    var dec = encoding.Decoder.init(enc.bytes.items);
    var column = try readVarU64Column(&dec);
    for (values) |value| {
        try std.testing.expectEqual(value, try column.read());
    }
    try column.expectEnd();
    try dec.expectEnd();
}

test "VarU64 column keeps raw encoding when RLE is larger" {
    const allocator = std.testing.allocator;
    const values = [_]u64{ 1, 2, 3 };

    var enc = encoding.Encoder.init(allocator);
    defer enc.deinit();
    try writeVarU64Column(&enc, allocator, &values);
    try std.testing.expectEqual(@as(u8, @intFromEnum(ByteColumnCodec.raw)), enc.bytes.items[0]);

    var dec = encoding.Decoder.init(enc.bytes.items);
    var column = try readVarU64Column(&dec);
    for (values) |value| {
        try std.testing.expectEqual(value, try column.read());
    }
    try column.expectEnd();
    try dec.expectEnd();
}

/// Write origin in a compact form; \
/// null origin               -> 0 bytes of id payload \
/// different client          -> client + clock \
/// same client, previous id  -> 0 bytes of id payload \
/// same client, other clock  -> only clock
fn writeOrigin(
    allocator: std.mem.Allocator,
    kinds: *std.ArrayList(u8),
    values: *encoding.Encoder,
    client: id.ClientId,
    clock: id.Clock,
    origin: ?id.Id,
) Error!void {
    const value = origin orelse {
        const null_kind: u8 = @intFromEnum(OriginKind.null);
        try kinds.append(allocator, null_kind);
        return;
    };

    if (value.client != client) {
        const full_id_kind: u8 = @intFromEnum(OriginKind.full_id);
        try kinds.append(allocator, full_id_kind);
        try writeId(values, value);
        return;
    }

    if (clock > 0 and value.clock == clock - 1) {
        const same_client_previous_clock_kind: u8 = @intFromEnum(OriginKind.same_client_previous_clock);
        try kinds.append(allocator, same_client_previous_clock_kind);
        return;
    }

    const same_client_clock_kind: u8 = @intFromEnum(OriginKind.same_client_clock);
    try kinds.append(allocator, same_client_clock_kind);
    try values.writeVarU64(value.clock);
}

fn firstStructAfterClock(
    items: []const item_mod.Item,
    handles: []const item_mod.ItemHandle,
    target_clock: id.Clock,
) ?usize {
    var left: usize = 0;
    var right: usize = handles.len;
    while (left < right) {
        const mid = left + (right - left) / 2;
        const candidate = items[handles[mid]];
        const candidate_end = candidate.id.clock + candidate.getClockLen();
        if (candidate_end <= target_clock) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    return if (left == handles.len) null else left;
}

test "findStructAfterClock returns correct index" {
    const create_struct = struct {
        fn create(client: id.ClientId, clock: id.Clock, len: id.Clock) item_mod.Item {
            return .{
                .id = .{ .client = client, .clock = clock },
                .content = .{ .string = .{ .bytes_start = 0, .bytes_len = 0, .logical_len = len } },
                .flags = item_mod.ItemFlags{
                    .countable = true,
                    .deleted = false,
                },
                .initial_left_origin_id = null,
                .initial_right_origin_id = null,
                .left = null,
                .right = null,
            };
        }
    }.create;
    const items: []const item_mod.Item = &.{
        create_struct(1, 0, 5),
        create_struct(1, 5, 5),
        create_struct(1, 10, 5),
    };
    const handles: []const item_mod.ItemHandle = &.{ 0, 1, 2 };

    const expectEqual = std.testing.expectEqual;
    try expectEqual(0, firstStructAfterClock(items, handles, 0) orelse unreachable);
    try expectEqual(0, firstStructAfterClock(items, handles, 3) orelse unreachable);
    try expectEqual(1, firstStructAfterClock(items, handles, 5) orelse unreachable);
    try expectEqual(1, firstStructAfterClock(items, handles, 7) orelse unreachable);
    try expectEqual(2, firstStructAfterClock(items, handles, 10) orelse unreachable);
    try expectEqual(2, firstStructAfterClock(items, handles, 12) orelse unreachable);
    try expectEqual(null, firstStructAfterClock(items, handles, 15));
}

/// Writes the cached delete set.
/// TODO: State vectors don't currently describe which
/// deletes the peer already knows, so updates still include the full set.
fn writeDeleteSet(view: EncodeView, enc: *encoding.Encoder) Error!void {
    const delete_set = &view.store.delete_set;
    try enc.writeVarU64(delete_set.clients.count());
    for (delete_set.clients.keys(), delete_set.clients.values()) |client, deletes| {
        try enc.writeVarU64(client);
        try enc.writeVarU64(deletes.items.len);
        for (deletes.items) |delete_item| {
            try enc.writeVarU64(delete_item.clock);
            try enc.writeVarU64(delete_item.len);
        }
    }
}

fn sliceBytes(view: EncodeView, slice: item_mod.TextSlice) []const u8 {
    const start: usize = slice.bytes_start;
    return view.bytes[start..][0..slice.bytes_len];
}

fn attributeKeyBytes(view: EncodeView, slice: item_mod.AttributeSlice) []const u8 {
    const start: usize = slice.key_start;
    return view.bytes[start..][0..slice.key_len];
}

fn attributeValueBytes(view: EncodeView, slice: item_mod.AttributeSlice) []const u8 {
    const start: usize = slice.value_start;
    return view.bytes[start..][0..slice.value_len];
}

pub fn validateUpdateBytes(update: []const u8) ReadUpdateError!void {
    const noop = struct {
        fn item(_: void, _: DecodedItem) ReadUpdateError!void {}
        fn deletedRange(_: void, _: DecodedDeleteRange) ReadUpdateError!void {}
    };
    try readUpdate(void, update, .{
        .context = {},
        .item = noop.item,
        .deletedRange = noop.deletedRange,
    });
}
