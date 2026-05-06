const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const store_mod = @import("store.zig");
const encoding = @import("encoding.zig");
const delete_set_mod = @import("delete_set.zig");
const utf = @import("utf.zig");

pub const update_magic = "MZCRDT2";
pub const update_version: u8 = 1;
pub const content_string_tag: u8 = 1;
pub const content_format_tag: u8 = 2;

pub const Error = error{
    InvalidUtf8,
    ScalarIndexOutOfBounds,
    InvalidUpdate,
    UnsupportedUpdateVersion,
    TextTooLarge,
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error || store_mod.StoreError;

pub const StateVector = std.array_hash_map.Auto(id.ClientId, id.Clock);

pub const EncodeView = struct {
    allocator: std.mem.Allocator,
    store: *const store_mod.StructStore,
    items: []const item_mod.Item,
    bytes: []const u8,
};

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

pub fn writeId(enc: *encoding.Encoder, value: id.Id) Error!void {
    try enc.writeVarU64(value.client);
    try enc.writeVarU64(value.clock);
}

pub fn readId(dec: *encoding.Decoder) Error!id.Id {
    return .{
        .client = try dec.readVarU64(),
        .clock = try dec.readVarU64(),
    };
}

fn writeStructs(view: EncodeView, enc: *encoding.Encoder, target_state: *const StateVector) Error!void {
    var changed_clients: usize = 0;
    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        const target_clock = target_state.get(client) orelse 0;
        for (client_structs.items.items) |handle| {
            const current = view.items[handle];
            if (current.id.clock + current.getClockLen() > target_clock) {
                changed_clients += 1;
                break;
            }
        }
    }

    try enc.writeVarU64(changed_clients);
    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        const target_clock = target_state.get(client) orelse 0;
        var item_count: usize = 0;
        for (client_structs.items.items) |handle| {
            const current = view.items[handle];
            if (current.id.clock + current.getClockLen() > target_clock) item_count += 1;
        }
        if (item_count == 0) continue;

        try enc.writeVarU64(client);
        try enc.writeVarU64(item_count);
        for (client_structs.items.items) |handle| {
            const current = view.items[handle];
            const current_len = current.getClockLen();
            if (current.id.clock + current_len <= target_clock) continue;
            const offset = if (target_clock > current.id.clock) target_clock - current.id.clock else 0;
            const write_id: id.Id = .{
                .client = current.id.client,
                .clock = current.id.clock + offset,
            };
            const write_len = current_len - offset;
            try enc.writeVarU64(write_id.clock);
            try enc.writeVarU64(write_len);
            var info: u8 = 0;
            const left_origin: ?id.Id = if (offset > 0)
                .{ .client = current.id.client, .clock = write_id.clock - 1 }
            else
                current.initial_left_origin_id;
            if (left_origin != null) info |= 1;
            if (current.initial_right_origin_id != null) info |= 2;
            try enc.writeByte(info);
            if (left_origin) |origin| try writeId(enc, origin);
            if (current.initial_right_origin_id) |right_origin| try writeId(enc, right_origin);
            switch (current.content) {
                .string => |slice| {
                    try enc.writeByte(content_string_tag);
                    const item_bytes = sliceBytes(view, slice);
                    const byte_offset = try utf.getByteOffsetForCharIndex(item_bytes, offset);
                    try enc.writeBytes(item_bytes[byte_offset..]);
                },
                .format => |format_slice| {
                    if (offset != 0) return error.InvalidUpdate;
                    try enc.writeByte(content_format_tag);
                    try enc.writeBytes(attributeKeyBytes(view, format_slice));
                    try enc.writeByte(if (format_slice.value_is_null) 1 else 0);
                    if (!format_slice.value_is_null) {
                        try enc.writeBytes(attributeValueBytes(view, format_slice));
                    }
                },
            }
        }
    }
}

fn writeDeleteSet(view: EncodeView, enc: *encoding.Encoder) Error!void {
    var ds: delete_set_mod.DeleteSet = .{};
    defer ds.deinit(view.allocator);

    for (view.store.clients.keys(), view.store.clients.values()) |client, client_structs| {
        var active_start: ?id.Clock = null;
        var active_len: id.Clock = 0;
        for (client_structs.items.items) |handle| {
            const current = view.items[handle];
            if (current.flags.deleted) {
                if (active_start == null) active_start = current.id.clock;
                active_len += current.getClockLen();
            } else if (active_start) |start_clock| {
                try ds.add(view.allocator, client, start_clock, active_len);
                active_start = null;
                active_len = 0;
            }
        }
        if (active_start) |start_clock| {
            try ds.add(view.allocator, client, start_clock, active_len);
        }
    }
    ds.sortAndMerge();

    try enc.writeVarU64(ds.clients.count());
    for (ds.clients.keys(), ds.clients.values()) |client, deletes| {
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
