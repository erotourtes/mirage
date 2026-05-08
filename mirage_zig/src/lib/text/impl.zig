const std = @import("std");
const id = @import("../id.zig");
const item_mod = @import("../item.zig");
const store_mod = @import("../store.zig");
const attrs = @import("../attrs.zig");
const utf = @import("../utf.zig");
const formatting = @import("../formatting.zig");
const delta_mod = @import("../delta.zig");
const search = @import("../search.zig");
const sync = @import("../sync.zig");
const integrate = @import("../integrate.zig");

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

    /// The first item in the linked list
    /// If it's `null`, the list is empty
    start: ?item_mod.ItemHandle = null,

    /// The visible text length (non-deleted, countable items)
    length: id.TextLen = 0,

    /// All items in the document.
    /// The elements are not necessarily in the document order.
    /// The document order is defined by the `left`/`right` fields of the items.
    ///
    /// `ItemHandle` is just the index in this array
    items: std.ArrayList(item_mod.Item) = .empty,

    /// A shared byte buffer holding the actual string data
    /// (both text and formatting attributes)
    ///
    /// `TextItem` doesn't own separate strings,
    /// but just slices of this buffer
    bytes: std.ArrayList(u8) = .empty,

    /// TODO:
    /// Client clock order, contrary to the `Item.left`/`right` which defines
    /// the document order.
    ///
    /// It answers the questions:
    /// - what clock should the next local item use
    /// - do we already have item {client_id, clock}
    /// - which item contains this clock
    /// - is there a clock gap in the client's history
    store: store_mod.StructStore = .{},

    /// Updates that arrived before their dependencies.
    /// They can't be applied yet
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

    pub fn len(self: *const TextImpl) id.TextLen {
        return self.length;
    }

    /// Inserts into the visible character index
    pub fn insert(self: *TextImpl, index: id.TextIndex, bytes: []const u8) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        const logical_len = try utf.countUnicodeLen(bytes);
        if (logical_len == 0) return;

        const pos = try self.findPosition(index);
        _ = try self.insertStringAt(pos, bytes);
    }

    /// Inserts string with formatting
    ///
    /// E.g inserting `C` with `bold: true` at index 1
    ///   0  1
    /// [A] [B]
    /// [A] [bold:true] [C] [bold:null] [B]
    pub fn insertWithAttrs(
        self: *TextImpl,
        index: id.TextIndex,
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
        index: id.TextIndex,
        format_len: id.TextLen,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        if (format_len > self.length - index) return error.IndexOutOfBounds;
        if (format_len == 0 or attributes.len == 0) return;

        const restore_attributes = try formatting.findRestoreAttr(
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

    /// Inserts a string into a `gap` defined by the position.
    /// .{ .left = 0, .right = 1 } means that the string
    /// will be inserted between items with handles 0 and 1.
    fn insertStringAt(self: *TextImpl, pos: Position, bytes: []const u8) TextError!item_mod.ItemHandle {
        const logical_len = try utf.countUnicodeLen(bytes);
        if (logical_len == 0) return error.IndexOutOfBounds;

        const bytes_len = try intCast(u32, bytes.len);
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
                .bytes_len = bytes_len,
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

    pub fn delete(self: *TextImpl, index: id.TextIndex, delete_len: id.TextLen) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        if (delete_len > self.length - index) return error.IndexOutOfBounds;
        if (delete_len == 0) return;

        var pos = try self.findPosition(index);
        var remaining = delete_len;
        while (remaining > 0) {
            const handle = pos.right orelse return error.IndexOutOfBounds;
            const current = self.items.items[handle];
            const is_visible = !current.flags.deleted and current.flags.countable;
            if (!is_visible) {
                pos = .{ .left = handle, .right = current.right };
                continue;
            }
            const current_len = current.getClockLen();
            const should_split = current_len > remaining;
            if (should_split) {
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
            defer cursor = current.right;
            const is_visible = !current.flags.deleted and current.flags.countable;
            if (!is_visible)
                continue;

            switch (current.content) {
                .string => |slice| try out.appendSlice(allocator, self.sliceBytes(slice)),
                .format => {},
            }
        }
        return try out.toOwnedSlice(allocator);
    }

    pub fn toDelta(self: *const TextImpl, allocator: std.mem.Allocator) TextError!attrs.Delta {
        return try delta_mod.toDelta(self, allocator);
    }

    fn encodeView(self: *const TextImpl) sync.EncodeView {
        return .{
            .allocator = self.allocator,
            .store = &self.store,
            .items = self.items.items,
            .bytes = self.bytes.items,
        };
    }

    /// Converts a visible character index into a position.
    /// Splits the item if the index is in the middle of it.
    ///
    /// Position returns a `gap`
    ///  0   1   2
    /// [A] [B] [C] -index: 1> { .left = 0, .right = 1 }
    ///
    /// Note if the character has formatting
    ///              0   1  2
    /// [{bold: true}] [A] [{bold: true}] -index: 1> { .left = 2, .right = null }
    fn findPosition(self: *TextImpl, index: id.TextIndex) TextError!Position {
        if (index > self.length) return error.IndexOutOfBounds;

        try self.search_cache.ensure(self);
        const nearest = self.search_cache.nearest(self, index);
        var remaining: id.TextLen = nearest.item_offset + (index - nearest.index);
        var left: ?item_mod.ItemHandle = if (nearest.handle) |handle| self.items.items[handle].left else null;
        var cursor = nearest.handle;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            defer {
                // Defer is ok, since return value is evaluated before; and they are scalar fields
                left = handle;
                cursor = current.right;
            }

            const is_visible = !current.flags.deleted and current.flags.countable;
            if (!is_visible) {
                continue;
            }

            const is_found = remaining == 0;
            if (is_found) {
                return .{ .left = left, .right = handle };
            }

            const current_len: id.TextLen = current.getClockLen();
            const is_within_current = remaining < current_len;
            if (is_within_current) {
                const right = try self.splitItem(handle, remaining);
                return .{ .left = handle, .right = right };
            }

            remaining -= current_len;
        }

        if (remaining != 0) return error.IndexOutOfBounds;
        return .{ .left = left, .right = null };
    }

    pub fn invalidateSearchMarkers(self: *TextImpl) void {
        self.search_cache.invalidate();
    }

    /// Splits the item at the given offset (in visible characters).
    /// FormatItems can't be split, since they don't have a visible length.
    ///
    /// Offset is the length of the left part after the split.
    /// [a, b, c] - offset: 1> [a] [b, c]
    ///
    /// If the offset is out of bounds returns the error.
    /// Returns the handle of the right part after the split.
    fn splitItem(self: *TextImpl, handle: item_mod.ItemHandle, offset: id.TextLen) TextError!item_mod.ItemHandle {
        const left_len = self.items.items[handle].getClockLen();
        const is_offset_out_of_bounds = offset == 0 or offset >= left_len;
        if (is_offset_out_of_bounds) return error.IndexOutOfBounds;

        const left_snapshot = self.items.items[handle];
        const slice = switch (left_snapshot.content) {
            .string => |string_slice| string_slice,
            .format => return error.UnsupportedContent,
        };
        const full_bytes = self.sliceBytes(slice);
        const byte_offset = try intCast(u32, try utf.getByteOffsetForCharIndex(full_bytes, offset));
        const right_bytes_len = slice.bytes_len - byte_offset;
        const right_len = left_snapshot.getClockLen() - offset;

        self.items.items[handle].content = .{ .string = .{
            .bytes_start = slice.bytes_start,
            .bytes_len = byte_offset,
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
                .bytes_start = slice.bytes_start + byte_offset,
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
        try sync.validateUpdateBytes(update);

        const callbacks = struct {
            const Context = struct {
                text: *TextImpl,
            };

            fn item(context: Context, decoded: sync.DecodedItem) sync.ReadUpdateError!void {
                const content: integrate.RemoteContent = switch (decoded.content) {
                    .string => |string| .{ .string = string },
                    .format => |format_content| .{ .format = .{
                        .key = format_content.key,
                        .value = format_content.value,
                    } },
                };
                try integrate.item(context.text, .{
                    .id = decoded.id,
                    .len = decoded.len,
                    .initial_left_origin_id = decoded.initial_left_origin_id,
                    .initial_right_origin_id = decoded.initial_right_origin_id,
                    .content = content,
                });
            }

            fn deletedRange(context: Context, decoded: sync.DecodedDeleteRange) sync.ReadUpdateError!void {
                try integrate.deletedRange(context.text, .{
                    .client = decoded.client,
                    .clock = decoded.clock,
                    .len = decoded.len,
                });
            }
        };

        try sync.readUpdate(callbacks.Context, update, .{
            .context = .{ .text = self },
            .item = callbacks.item,
            .deletedRange = callbacks.deletedRange,
        });
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

    /// Returns the `new_item` handle
    pub fn appendItem(self: *TextImpl, new_item: item_mod.Item) TextError!item_mod.ItemHandle {
        const handle = try intCast(item_mod.ItemHandle, self.items.items.len);
        try self.items.append(self.allocator, new_item);
        return handle;
    }

    /// Returns the start index of the appended bytes in the shared byte buffer.
    pub fn appendBytes(self: *TextImpl, source: []const u8) TextError!u32 {
        const start = try intCast(u32, self.bytes.items.len);
        try self.bytes.appendSlice(self.allocator, source);
        return start;
    }

    pub fn appendAttribute(self: *TextImpl, attribute: attrs.Attribute) TextError!item_mod.AttributeSlice {
        const key_start = try self.appendBytes(attribute.key);
        const key_len = try intCast(u32, attribute.key.len);
        return switch (attribute.value) {
            .null => .{
                .key_start = key_start,
                .key_len = key_len,
                .value_is_null = true,
            },
            .string => |value| .{
                .key_start = key_start,
                .key_len = key_len,
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

fn intCast(comptime T: type, value: anytype) error{TextTooLarge}!T {
    return std.math.cast(T, value) orelse error.TextTooLarge;
}

//==============================================================================
// findPosition
//==============================================================================
test "findPosition returns gap before item at exact boundary" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "A");
    try text.insert(1, "B");
    try text.insert(2, "C");

    const position = try text.findPosition(1);

    try std.testing.expectEqual(0, position.left);
    try std.testing.expectEqual(1, position.right);
}

test "findPosition splits item when index is inside visible text item" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "ABC");

    const position = try text.findPosition(1);

    try std.testing.expectEqual(0, position.left);
    try std.testing.expectEqual(1, position.right);

    try std.testing.expectEqual(1, text.items.items[0].getClockLen());
    try std.testing.expectEqual(2, text.items.items[1].getClockLen());
}

test "findPosition returns end gap at document length" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "A");
    try text.insert(1, "B");

    const position = try text.findPosition(text.len());

    try std.testing.expectEqual(1, position.left);
    try std.testing.expectEqual(null, position.right);
}

test "findPosition tracks invisible items in linked-list gap" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    const bold = attrs.Attribute{
        .key = "bold",
        .value = .{ .string = "true" },
    };

    try text.insertWithAttrs(0, "A", &.{bold});

    const position = try text.findPosition(1);

    try std.testing.expectEqual(2, position.left);
    try std.testing.expectEqual(null, position.right);
}

//==============================================================================
// splitItem
//==============================================================================

test "splitItem splits string item at given offset" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "ABC");

    const right_handle = try text.splitItem(0, 1);

    try std.testing.expectEqual(1, text.items.items[0].getClockLen());
    try std.testing.expectEqual(2, text.items.items[right_handle].getClockLen());
    try std.testing.expectEqualStrings("A", text.sliceBytes(text.items.items[0].content.string));
    try std.testing.expectEqualStrings("BC", text.sliceBytes(text.items.items[right_handle].content.string));
    try std.testing.expectEqual(0, text.items.items[1].left);
}

test "splitItem splits string item at the end" {
    const allocator = std.testing.allocator;
    var text = TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "ABC");

    const right_handle = text.splitItem(0, 3);
    try std.testing.expectError(error.IndexOutOfBounds, right_handle);
}
