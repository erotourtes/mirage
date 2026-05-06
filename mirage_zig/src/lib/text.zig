const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const store_mod = @import("store.zig");
const encoding = @import("encoding.zig");
const attrs = @import("attrs.zig");
const utf = @import("utf.zig");
const formatting = @import("formatting.zig");
const delta_mod = @import("delta.zig");
const search = @import("search.zig");
const debug_mod = @import("debug.zig");
const sync = @import("sync.zig");
const integrate = @import("integrate.zig");

pub const TextError = error{
    IndexOutOfBounds,
    InvalidHandle,
    InvalidUtf8,
    ScalarIndexOutOfBounds,
    TextTooLarge,
    ItemTooLarge,
    UnsupportedContent,
    MissingDependency,
    InvalidUpdate,
    UnsupportedUpdateVersion,
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error || store_mod.StoreError;

const Position = struct {
    left: ?item_mod.ItemHandle,
    right: ?item_mod.ItemHandle,
};

pub const TextImpl = struct {
    allocator: std.mem.Allocator,
    client_id: id.ClientId,
    start: ?item_mod.ItemHandle = null,
    length: id.Clock = 0,
    items: std.ArrayList(item_mod.Item) = .empty,
    bytes: std.ArrayList(u8) = .empty,
    store: store_mod.StructStore = .{},
    pending_updates: std.ArrayList([]u8) = .empty,
    search_cache: search.Cache = .{},

    pub fn init(allocator: std.mem.Allocator, client_id: id.ClientId) TextImpl {
        return .{
            .allocator = allocator,
            .client_id = client_id,
        };
    }

    pub fn deinit(self: *TextImpl) void {
        for (self.pending_updates.items) |pending| {
            self.allocator.free(pending);
        }
        self.pending_updates.deinit(self.allocator);
        self.search_cache.deinit(self.allocator);
        self.store.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn len(self: *const TextImpl) id.Clock {
        return self.length;
    }

    pub fn insert(self: *TextImpl, index: id.Clock, bytes: []const u8) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        const logical_len = try utf.countUnicodeLen(bytes);
        if (logical_len == 0) return;

        const pos = try self.findPosition(index);
        _ = try self.insertStringAt(pos, bytes);
    }

    pub fn insertWithAttrs(
        self: *TextImpl,
        index: id.Clock,
        bytes: []const u8,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        const logical_len = try utf.countUnicodeLen(bytes);
        if (logical_len == 0) return;

        var pos = try self.findPosition(index);
        for (attributes) |attribute| {
            const marker = try self.insertFormatAt(pos, attribute);
            pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        const string_handle = try self.insertStringAt(pos, bytes);
        pos = .{ .left = string_handle, .right = self.items.items[string_handle].right };
        for (attributes) |attribute| {
            const marker = try self.insertFormatAt(pos, .{
                .key = attribute.key,
                .value = .null,
            });
            pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        try self.cleanupFormatting();
    }

    pub fn format(
        self: *TextImpl,
        index: id.Clock,
        format_len: id.Clock,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        if (format_len > self.length - index) return error.IndexOutOfBounds;
        if (format_len == 0 or attributes.len == 0) return;

        const restore_attributes = try formatting.restoreAttributesAt(
            self,
            self.allocator,
            index + format_len,
            attributes,
        );
        defer formatting.freeOwnedAttributes(self.allocator, restore_attributes);

        var start_pos = try self.findPosition(index);
        for (attributes) |attribute| {
            const marker = try self.insertFormatAt(start_pos, attribute);
            start_pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        var end_pos = try self.findPosition(index + format_len);
        for (restore_attributes) |owned_attribute| {
            const marker = try self.insertFormatAt(end_pos, owned_attribute.attribute);
            end_pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        try self.cleanupFormatting();
    }

    fn insertStringAt(self: *TextImpl, pos: Position, bytes: []const u8) TextError!item_mod.ItemHandle {
        const logical_len = try utf.countUnicodeLen(bytes);
        if (logical_len == 0) return error.IndexOutOfBounds;

        const bytes_start = try self.appendBytes(bytes);
        const handle = try self.appendItem(.{
            .id = .{
                .client = self.client_id,
                .clock = self.store.getState(self.items.items, self.client_id),
            },
            .initial_left_origin_id = if (pos.left) |left| self.items.items[left].getLastId() else null,
            .initial_right_origin_id = if (pos.right) |right| self.items.items[right].id else null,
            .left = pos.left,
            .right = pos.right,
            .content = .{ .string = .{
                .bytes_start = bytes_start,
                .bytes_len = try intCast(u32, bytes.len),
                .logical_len = logical_len,
            } },
            .flags = .{
                .countable = true,
                .deleted = false,
            },
        });

        try self.store.addStruct(self.allocator, self.items.items, handle);
        self.linkInserted(handle, pos.left, pos.right);
        self.length += logical_len;
        return handle;
    }

    fn insertFormatAt(self: *TextImpl, pos: Position, attribute: attrs.Attribute) TextError!item_mod.ItemHandle {
        const content = try self.appendAttribute(attribute);
        const handle = try self.appendItem(.{
            .id = .{
                .client = self.client_id,
                .clock = self.store.getState(self.items.items, self.client_id),
            },
            .initial_left_origin_id = if (pos.left) |left| self.items.items[left].getLastId() else null,
            .initial_right_origin_id = if (pos.right) |right| self.items.items[right].id else null,
            .left = pos.left,
            .right = pos.right,
            .content = .{ .format = content },
            .flags = .{
                .countable = false,
                .deleted = false,
            },
        });

        try self.store.addStruct(self.allocator, self.items.items, handle);
        self.linkInserted(handle, pos.left, pos.right);
        return handle;
    }

    pub fn delete(self: *TextImpl, index: id.Clock, delete_len: id.Clock) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        if (delete_len > self.length - index) return error.IndexOutOfBounds;
        if (delete_len == 0) return;

        var pos = try self.findPosition(index);
        var remaining = delete_len;
        while (remaining > 0) {
            const handle = pos.right orelse return error.IndexOutOfBounds;
            const current = self.items.items[handle];
            if (current.flags.deleted or !current.flags.countable) {
                pos = .{ .left = handle, .right = current.right };
                continue;
            }
            const current_len = current.getClockLen();
            if (current_len > remaining) {
                _ = try self.splitItem(handle, remaining);
            }

            const delete_handle = handle;
            const deleted_len = self.items.items[delete_handle].getClockLen();
            self.items.items[delete_handle].flags.deleted = true;
            self.invalidateSearchMarkers();
            self.length -= deleted_len;
            remaining -= deleted_len;
            pos = .{
                .left = delete_handle,
                .right = self.items.items[delete_handle].right,
            };
        }
        try self.cleanupFormatting();
    }

    pub fn encodeStateVector(self: *const TextImpl, allocator: std.mem.Allocator) TextError![]u8 {
        return try sync.encodeStateVector(self.encodeView(), allocator);
    }

    pub fn encodeStateAsUpdate(
        self: *const TextImpl,
        allocator: std.mem.Allocator,
        encoded_target_state_vector: ?[]const u8,
    ) TextError![]u8 {
        return try sync.encodeStateAsUpdate(self.encodeView(), allocator, encoded_target_state_vector);
    }

    pub fn applyUpdate(self: *TextImpl, update: []const u8) TextError!void {
        self.applyUpdateOnce(update) catch |err| switch (err) {
            error.MissingDependency => {
                const copy = try self.allocator.dupe(u8, update);
                errdefer self.allocator.free(copy);
                try self.pending_updates.append(self.allocator, copy);
                return;
            },
            else => return err,
        };
        try self.retryPendingUpdates();
    }

    pub fn toOwnedString(self: *const TextImpl, allocator: std.mem.Allocator) TextError![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);

        var cursor = self.start;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            if (!current.flags.deleted and current.flags.countable) {
                switch (current.content) {
                    .string => |slice| try out.appendSlice(allocator, self.sliceBytes(slice)),
                    .format => {},
                }
            }
            cursor = current.right;
        }
        return try out.toOwnedSlice(allocator);
    }

    pub fn toDelta(self: *const TextImpl, allocator: std.mem.Allocator) TextError!attrs.Delta {
        return try delta_mod.toDelta(self, allocator);
    }

    fn debugView(self: *const TextImpl) debug_mod.View {
        return .{
            .store = &self.store,
            .items = self.items.items,
            .bytes = self.bytes.items,
            .start = self.start,
            .length = self.length,
            .pending_update_count = self.pending_updates.items.len,
            .search_markers_valid = self.search_cache.isValid(),
            .search_marker_count = self.search_cache.count(),
        };
    }

    fn encodeView(self: *const TextImpl) sync.EncodeView {
        return .{
            .allocator = self.allocator,
            .store = &self.store,
            .items = self.items.items,
            .bytes = self.bytes.items,
        };
    }

    fn findPosition(self: *TextImpl, index: id.Clock) TextError!Position {
        if (index > self.length) return error.IndexOutOfBounds;

        try self.search_cache.ensure(self);
        const nearest = self.search_cache.nearest(self, index);
        var remaining = nearest.item_offset + (index - nearest.index);
        var left: ?item_mod.ItemHandle = if (nearest.handle) |handle| self.items.items[handle].left else null;
        var cursor = nearest.handle;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            if (!current.flags.deleted and current.flags.countable) {
                if (remaining == 0) {
                    return .{ .left = left, .right = handle };
                }
                const current_len = current.getClockLen();
                if (remaining < current_len) {
                    const right = try self.splitItem(handle, remaining);
                    return .{ .left = handle, .right = right };
                }
                remaining -= current_len;
            }
            left = handle;
            cursor = current.right;
        }

        if (remaining != 0) return error.IndexOutOfBounds;
        return .{ .left = left, .right = null };
    }

    pub fn invalidateSearchMarkers(self: *TextImpl) void {
        self.search_cache.invalidate();
    }

    fn splitItem(self: *TextImpl, handle: item_mod.ItemHandle, offset: id.Clock) TextError!item_mod.ItemHandle {
        const left_len = self.items.items[handle].getClockLen();
        if (offset == 0 or offset >= left_len) return handle;

        const left_snapshot = self.items.items[handle];
        const slice = switch (left_snapshot.content) {
            .string => |string_slice| string_slice,
            .format => return error.UnsupportedContent,
        };
        const full_bytes = self.sliceBytes(slice);
        const byte_offset = try utf.getByteOffsetForCharIndex(full_bytes, offset);
        const right_bytes_len = slice.bytes_len - try intCast(u32, byte_offset);
        const right_len = left_snapshot.getClockLen() - offset;

        self.items.items[handle].content = .{ .string = .{
            .bytes_start = slice.bytes_start,
            .bytes_len = try intCast(u32, byte_offset),
            .logical_len = offset,
        } };

        const right_handle = try self.appendItem(.{
            .id = .{
                .client = left_snapshot.id.client,
                .clock = left_snapshot.id.clock + offset,
            },
            .initial_left_origin_id = self.items.items[handle].getLastId(),
            .initial_right_origin_id = left_snapshot.initial_right_origin_id,
            .left = handle,
            .right = left_snapshot.right,
            .content = .{ .string = .{
                .bytes_start = slice.bytes_start + try intCast(u32, byte_offset),
                .bytes_len = right_bytes_len,
                .logical_len = right_len,
            } },
            .flags = left_snapshot.flags,
        });

        self.items.items[handle].right = right_handle;
        if (left_snapshot.right) |old_right| {
            self.items.items[old_right].left = right_handle;
        }
        try self.store.insertStructAfter(self.allocator, self.items.items, handle, right_handle);
        self.invalidateSearchMarkers();
        return right_handle;
    }

    pub fn getItemCleanStart(self: *TextImpl, target: id.Id) TextError!item_mod.ItemHandle {
        const handle = try self.store.findHandleById(self.items.items, target);
        const current = self.items.items[handle];
        if (current.id.clock < target.clock) {
            return try self.splitItem(handle, target.clock - current.id.clock);
        }
        return handle;
    }

    pub fn getItemCleanEnd(self: *TextImpl, target: id.Id) TextError!item_mod.ItemHandle {
        const handle = try self.store.findHandleById(self.items.items, target);
        const current = self.items.items[handle];
        const offset = target.clock - current.id.clock + 1;
        if (offset < current.getClockLen()) {
            _ = try self.splitItem(handle, offset);
        }
        return handle;
    }

    fn cleanupFormatting(self: *TextImpl) TextError!void {
        try formatting.cleanup(self);
    }

    fn retryPendingUpdates(self: *TextImpl) TextError!void {
        var index: usize = 0;
        while (index < self.pending_updates.items.len) {
            const pending = self.pending_updates.items[index];
            self.applyUpdateOnce(pending) catch |err| switch (err) {
                error.MissingDependency => {
                    index += 1;
                    continue;
                },
                else => return err,
            };
            const removed = self.pending_updates.orderedRemove(index);
            self.allocator.free(removed);
            index = 0;
        }
    }

    fn applyUpdateOnce(self: *TextImpl, update: []const u8) TextError!void {
        try validateUpdateBytes(update);

        var dec = encoding.Decoder.init(update);
        const magic = try dec.readRaw(sync.update_magic.len);
        if (!std.mem.eql(u8, magic, sync.update_magic)) return error.InvalidUpdate;
        const version = try dec.readByte();
        if (version != sync.update_version) return error.UnsupportedUpdateVersion;

        const client_count = try dec.readVarU64();
        var client_index: usize = 0;
        while (client_index < client_count) : (client_index += 1) {
            const client = try dec.readVarU64();
            const item_count = try dec.readVarU64();
            var item_index: usize = 0;
            while (item_index < item_count) : (item_index += 1) {
                const clock = try dec.readVarU64();
                const len_value = try dec.readVarU64();
                const info = try dec.readByte();
                const left_origin = if ((info & 1) != 0) try sync.readId(&dec) else null;
                const right_origin = if ((info & 2) != 0) try sync.readId(&dec) else null;
                const content_tag = try dec.readByte();
                const content: integrate.RemoteContent = switch (content_tag) {
                    sync.content_string_tag => blk: {
                        const string_bytes = try dec.readBytes();
                        const logical_len = try utf.countUnicodeLen(string_bytes);
                        if (logical_len != len_value) return error.InvalidUpdate;
                        break :blk .{ .string = string_bytes };
                    },
                    sync.content_format_tag => blk: {
                        if (len_value != 1) return error.InvalidUpdate;
                        const key = try dec.readBytes();
                        const value_is_null = (try dec.readByte()) != 0;
                        const value: attrs.AttributeValue = if (value_is_null)
                            .null
                        else
                            .{ .string = try dec.readBytes() };
                        break :blk .{ .format = .{ .key = key, .value = value } };
                    },
                    else => return error.UnsupportedContent,
                };
                try integrate.item(self, .{
                    .id = .{ .client = client, .clock = clock },
                    .len = len_value,
                    .initial_left_origin_id = left_origin,
                    .initial_right_origin_id = right_origin,
                    .content = content,
                });
            }
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
                try integrate.deletedRange(self, client, clock, delete_len);
            }
        }
        try dec.expectEnd();
    }

    pub fn linkInserted(
        self: *TextImpl,
        handle: item_mod.ItemHandle,
        left: ?item_mod.ItemHandle,
        right: ?item_mod.ItemHandle,
    ) void {
        if (left) |left_handle| {
            self.items.items[left_handle].right = handle;
        } else {
            self.start = handle;
        }
        if (right) |right_handle| {
            self.items.items[right_handle].left = handle;
        }
        self.items.items[handle].left = left;
        self.items.items[handle].right = right;
        self.invalidateSearchMarkers();
    }

    pub fn appendItem(self: *TextImpl, new_item: item_mod.Item) TextError!item_mod.ItemHandle {
        const handle = try intCast(item_mod.ItemHandle, self.items.items.len);
        try self.items.append(self.allocator, new_item);
        return handle;
    }

    pub fn appendBytes(self: *TextImpl, source: []const u8) TextError!u32 {
        const start = try intCast(u32, self.bytes.items.len);
        try self.bytes.appendSlice(self.allocator, source);
        return start;
    }

    pub fn appendAttribute(self: *TextImpl, attribute: attrs.Attribute) TextError!item_mod.AttributeSlice {
        const key_start = try self.appendBytes(attribute.key);
        return switch (attribute.value) {
            .null => .{
                .key_start = key_start,
                .key_len = try intCast(u32, attribute.key.len),
                .value_is_null = true,
            },
            .string => |value| .{
                .key_start = key_start,
                .key_len = try intCast(u32, attribute.key.len),
                .value_start = try self.appendBytes(value),
                .value_len = try intCast(u32, value.len),
                .value_is_null = false,
            },
        };
    }

    pub fn sliceBytes(self: *const TextImpl, slice: item_mod.TextSlice) []const u8 {
        const start: usize = slice.bytes_start;
        return self.bytes.items[start..][0..slice.bytes_len];
    }

    pub fn attributeKeyBytes(self: *const TextImpl, slice: item_mod.AttributeSlice) []const u8 {
        const start: usize = slice.key_start;
        return self.bytes.items[start..][0..slice.key_len];
    }

    pub fn attributeValueBytes(self: *const TextImpl, slice: item_mod.AttributeSlice) []const u8 {
        const start: usize = slice.value_start;
        return self.bytes.items[start..][0..slice.value_len];
    }
};

/// One replicated text CRDT document.
///
/// Public indexes are Unicode scalar indexes over valid UTF-8 text. Returned
/// byte slices and deltas that take an allocator are owned by the caller unless
/// the function states otherwise.
pub const Text = struct {
    /// Implementation storage. Prefer the methods on `Text`; this field exists
    /// so `Text` can keep value semantics without heap-allocating its body.
    impl: TextImpl,

    /// Creates an empty text document for `client_id`.
    ///
    /// The allocator is retained by the document and used for all internal
    /// storage until `deinit` is called.
    pub fn init(allocator: std.mem.Allocator, client_id: id.ClientId) Text {
        return .{ .impl = TextImpl.init(allocator, client_id) };
    }

    /// Frees all storage owned by this text document.
    pub fn deinit(self: *Text) void {
        self.impl.deinit();
        self.* = undefined;
    }

    /// Returns the visible document length in Unicode scalar values.
    pub fn len(self: *const Text) id.Clock {
        return self.impl.len();
    }

    /// Inserts valid UTF-8 bytes at `index`.
    ///
    /// `index` is a Unicode scalar index. Empty text is a no-op. `bytes` are
    /// copied into the document before this function returns.
    pub fn insert(self: *Text, index: id.Clock, bytes: []const u8) TextError!void {
        try self.impl.insert(index, bytes);
    }

    /// Inserts valid UTF-8 bytes with formatting attributes at `index`.
    ///
    /// Attribute keys and string values are copied into the document. Attribute
    /// values support only `null` and string values.
    pub fn insertWithAttrs(
        self: *Text,
        index: id.Clock,
        bytes: []const u8,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        try self.impl.insertWithAttrs(index, bytes, attributes);
    }

    /// Applies formatting attributes to an existing visible range.
    ///
    /// `index` and `format_len` are Unicode scalar units. A `null` attribute
    /// value clears that attribute over the formatted range.
    pub fn format(
        self: *Text,
        index: id.Clock,
        format_len: id.Clock,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        try self.impl.format(index, format_len, attributes);
    }

    /// Deletes `delete_len` visible Unicode scalars starting at `index`.
    pub fn delete(self: *Text, index: id.Clock, delete_len: id.Clock) TextError!void {
        try self.impl.delete(index, delete_len);
    }

    /// Encodes this document's state vector.
    ///
    /// The returned byte slice is allocated with `allocator` and must be freed
    /// by the caller.
    pub fn encodeStateVector(self: *const Text, allocator: std.mem.Allocator) TextError![]u8 {
        return try self.impl.encodeStateVector(allocator);
    }

    /// Encodes an update from `encoded_target_state_vector` to the current state.
    ///
    /// Pass `null` to encode the whole document state. The returned byte slice
    /// is allocated with `allocator` and must be freed by the caller.
    pub fn encodeStateAsUpdate(
        self: *const Text,
        allocator: std.mem.Allocator,
        encoded_target_state_vector: ?[]const u8,
    ) TextError![]u8 {
        return try self.impl.encodeStateAsUpdate(allocator, encoded_target_state_vector);
    }

    /// Applies an update produced by `encodeStateAsUpdate`.
    ///
    /// Updates with missing dependencies are retained internally and retried
    /// after later successful updates.
    pub fn applyUpdate(self: *Text, update: []const u8) TextError!void {
        try self.impl.applyUpdate(update);
    }

    /// Renders the visible document text as owned UTF-8 bytes.
    ///
    /// The returned byte slice is allocated with `allocator` and must be freed
    /// by the caller.
    pub fn toOwnedString(self: *const Text, allocator: std.mem.Allocator) TextError![]u8 {
        return try self.impl.toOwnedString(allocator);
    }

    /// Renders the document as attributed insert operations.
    ///
    /// The returned delta owns all inserted strings and copied attributes. Call
    /// `Delta.deinit` with the same allocator when done.
    pub fn toDelta(self: *const Text, allocator: std.mem.Allocator) TextError!attrs.Delta {
        return try self.impl.toDelta(allocator);
    }
};

pub const debug = struct {
    pub fn checkIntegrity(text: *const Text) TextError!void {
        try debug_mod.checkIntegrity(text.impl.debugView());
    }

    pub fn itemCount(text: *const Text) usize {
        return debug_mod.itemCount(text.impl.debugView());
    }

    pub fn itemLen(text: *const Text, index: usize) id.Clock {
        return debug_mod.itemLen(text.impl.debugView(), index);
    }

    pub fn itemDeleted(text: *const Text, index: usize) bool {
        return debug_mod.itemDeleted(text.impl.debugView(), index);
    }

    pub fn findHandleById(text: *const Text, target: id.Id) TextError!item_mod.ItemHandle {
        return try debug_mod.findHandleById(text.impl.debugView(), target);
    }

    pub fn clientState(text: *const Text, client: id.ClientId) id.Clock {
        return debug_mod.clientState(text.impl.debugView(), client);
    }

    pub fn pendingUpdateCount(text: *const Text) usize {
        return debug_mod.pendingUpdateCount(text.impl.debugView());
    }

    pub fn ensureSearchMarkers(text: *Text) TextError!void {
        try text.impl.search_cache.ensure(&text.impl);
    }

    pub fn searchMarkersValid(text: *const Text) bool {
        return debug_mod.searchMarkersValid(text.impl.debugView());
    }

    pub fn searchMarkerCount(text: *const Text) usize {
        return debug_mod.searchMarkerCount(text.impl.debugView());
    }

    pub fn liveFormatMarkerCount(text: *const Text, key: []const u8, value: ?[]const u8) usize {
        return debug_mod.liveFormatMarkerCount(text.impl.debugView(), key, value);
    }
};

fn intCast(comptime T: type, value: anytype) error{TextTooLarge}!T {
    return std.math.cast(T, value) orelse error.TextTooLarge;
}

fn validateUpdateBytes(update: []const u8) TextError!void {
    var dec = encoding.Decoder.init(update);
    const magic = try dec.readRaw(sync.update_magic.len);
    if (!std.mem.eql(u8, magic, sync.update_magic)) return error.InvalidUpdate;
    const version = try dec.readByte();
    if (version != sync.update_version) return error.UnsupportedUpdateVersion;

    const client_count = try dec.readVarU64();
    var client_index: usize = 0;
    while (client_index < client_count) : (client_index += 1) {
        _ = try dec.readVarU64();
        const item_count = try dec.readVarU64();
        var item_index: usize = 0;
        while (item_index < item_count) : (item_index += 1) {
            _ = try dec.readVarU64();
            const len_value = try dec.readVarU64();
            const info = try dec.readByte();
            if ((info & 1) != 0) _ = try sync.readId(&dec);
            if ((info & 2) != 0) _ = try sync.readId(&dec);
            const content_tag = try dec.readByte();
            switch (content_tag) {
                sync.content_string_tag => {
                    const string_bytes = try dec.readBytes();
                    const logical_len = try utf.countUnicodeLen(string_bytes);
                    if (logical_len != len_value) return error.InvalidUpdate;
                },
                sync.content_format_tag => {
                    if (len_value != 1) return error.InvalidUpdate;
                    _ = try dec.readBytes();
                    const value_is_null = (try dec.readByte()) != 0;
                    if (!value_is_null) _ = try dec.readBytes();
                },
                else => return error.UnsupportedContent,
            }
        }
    }

    const delete_client_count = try dec.readVarU64();
    var delete_client_index: usize = 0;
    while (delete_client_index < delete_client_count) : (delete_client_index += 1) {
        _ = try dec.readVarU64();
        const delete_count = try dec.readVarU64();
        var delete_index: usize = 0;
        while (delete_index < delete_count) : (delete_index += 1) {
            _ = try dec.readVarU64();
            _ = try dec.readVarU64();
        }
    }
    try dec.expectEnd();
}
