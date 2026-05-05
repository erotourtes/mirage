const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const store_mod = @import("store.zig");
const encoding = @import("encoding.zig");
const delete_set_mod = @import("delete_set.zig");
const attrs = @import("attrs.zig");
const utf = @import("utf.zig");

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
    VarIntOverflow,
    TrailingBytes,
} || std.mem.Allocator.Error || store_mod.StoreError;

const update_magic = "MZCRDT2";
const content_string_tag: u8 = 1;
const content_format_tag: u8 = 2;

const Position = struct {
    left: ?item_mod.ItemHandle,
    right: ?item_mod.ItemHandle,
};

const SearchMarker = struct {
    index: id.Clock,
    handle: item_mod.ItemHandle,
    item_offset: id.Clock,
};

const search_marker_step: id.Clock = 32;

const StateVector = std.AutoArrayHashMapUnmanaged(id.ClientId, id.Clock);

const RemoteItem = struct {
    id: id.Id,
    len: id.Clock,
    initial_left_origin_id: ?id.Id,
    initial_right_origin_id: ?id.Id,
    content: RemoteContent,
};

const RemoteContent = union(enum) {
    string: []const u8,
    format: RemoteFormat,
};

const RemoteFormat = struct {
    key: []const u8,
    value: attrs.AttributeValue,
};

pub const Text = struct {
    allocator: std.mem.Allocator,
    client_id: id.ClientId,
    start: ?item_mod.ItemHandle = null,
    length: id.Clock = 0,
    items: std.ArrayList(item_mod.Item) = .empty,
    bytes: std.ArrayList(u8) = .empty,
    store: store_mod.StructStore = .{},
    pending_updates: std.ArrayList([]u8) = .empty,
    search_markers: std.ArrayList(SearchMarker) = .empty,
    search_markers_valid: bool = false,

    pub fn init(allocator: std.mem.Allocator, client_id: id.ClientId) Text {
        return .{
            .allocator = allocator,
            .client_id = client_id,
        };
    }

    pub fn deinit(self: *Text) void {
        for (self.pending_updates.items) |pending| {
            self.allocator.free(pending);
        }
        self.pending_updates.deinit(self.allocator);
        self.search_markers.deinit(self.allocator);
        self.store.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
        self.items.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn len(self: *const Text) id.Clock {
        return self.length;
    }

    pub fn insert(self: *Text, index: id.Clock, bytes: []const u8) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        const logical_len = try utf.scalarCount(bytes);
        if (logical_len == 0) return;

        const pos = try self.findPosition(index);
        _ = try self.insertStringAt(pos, bytes);
    }

    pub fn insertWithAttrs(
        self: *Text,
        index: id.Clock,
        bytes: []const u8,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        const logical_len = try utf.scalarCount(bytes);
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
        self: *Text,
        index: id.Clock,
        format_len: id.Clock,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        if (index > self.length) return error.IndexOutOfBounds;
        if (format_len > self.length - index) return error.IndexOutOfBounds;
        if (format_len == 0 or attributes.len == 0) return;

        var start_pos = try self.findPosition(index);
        for (attributes) |attribute| {
            const marker = try self.insertFormatAt(start_pos, attribute);
            start_pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        var end_pos = try self.findPosition(index + format_len);
        for (attributes) |attribute| {
            const marker = try self.insertFormatAt(end_pos, .{
                .key = attribute.key,
                .value = .null,
            });
            end_pos = .{ .left = marker, .right = self.items.items[marker].right };
        }
        try self.cleanupFormatting();
    }

    fn insertStringAt(self: *Text, pos: Position, bytes: []const u8) TextError!item_mod.ItemHandle {
        const logical_len = try utf.scalarCount(bytes);
        if (logical_len == 0) return error.IndexOutOfBounds;

        const bytes_start = try self.appendBytes(bytes);
        const handle = try self.appendItem(.{
            .id = .{
                .client = self.client_id,
                .clock = self.store.getState(self.items.items, self.client_id),
            },
            .len = logical_len,
            .initial_left_origin_id = if (pos.left) |left| self.items.items[left].lastId() else null,
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

    fn insertFormatAt(self: *Text, pos: Position, attribute: attrs.Attribute) TextError!item_mod.ItemHandle {
        const content = try self.appendAttribute(attribute);
        const handle = try self.appendItem(.{
            .id = .{
                .client = self.client_id,
                .clock = self.store.getState(self.items.items, self.client_id),
            },
            .len = 1,
            .initial_left_origin_id = if (pos.left) |left| self.items.items[left].lastId() else null,
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

    pub fn delete(self: *Text, index: id.Clock, delete_len: id.Clock) TextError!void {
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
            if (current.len > remaining) {
                _ = try self.splitItem(handle, remaining);
            }

            const delete_handle = handle;
            const deleted_len = self.items.items[delete_handle].len;
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

    pub fn encodeStateVector(self: *const Text, allocator: std.mem.Allocator) TextError![]u8 {
        var enc = encoding.Encoder.init(allocator);
        errdefer enc.deinit();

        try enc.writeVarU64(self.store.clients.count());
        for (self.store.clients.keys(), self.store.clients.values()) |client, client_structs| {
            if (client_structs.items.items.len == 0) continue;
            try enc.writeVarU64(client);
            try enc.writeVarU64(self.store.getState(self.items.items, client));
        }
        return try enc.toOwnedSlice();
    }

    pub fn encodeStateAsUpdate(
        self: *const Text,
        allocator: std.mem.Allocator,
        encoded_target_state_vector: ?[]const u8,
    ) TextError![]u8 {
        var target_state = try decodeStateVector(self.allocator, encoded_target_state_vector orelse &.{});
        defer target_state.deinit(self.allocator);

        var enc = encoding.Encoder.init(allocator);
        errdefer enc.deinit();

        try enc.bytes.appendSlice(allocator, update_magic);
        try self.writeStructs(&enc, &target_state);
        try self.writeDeleteSet(&enc);
        return try enc.toOwnedSlice();
    }

    pub fn applyUpdate(self: *Text, update: []const u8) TextError!void {
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

    pub fn toOwnedString(self: *const Text, allocator: std.mem.Allocator) ![]u8 {
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

    pub fn toDelta(self: *const Text, allocator: std.mem.Allocator) TextError!attrs.Delta {
        var delta: attrs.Delta = .{};
        errdefer delta.deinit(allocator);

        var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
        defer active_attrs.deinit(allocator);

        var cursor = self.start;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            if (!current.flags.deleted) {
                switch (current.content) {
                    .format => |format_slice| try updateActiveAttrs(self, allocator, &active_attrs, format_slice),
                    .string => |slice| if (current.flags.countable) {
                        const inserted_text = try allocator.dupe(u8, self.sliceBytes(slice));
                        errdefer allocator.free(inserted_text);
                        const copied_attrs = try copyAttributes(allocator, active_attrs.items);
                        errdefer freeAttributes(allocator, copied_attrs);
                        try delta.ops.append(allocator, .{
                            .insert = inserted_text,
                            .attributes = copied_attrs,
                        });
                    },
                }
            }
            cursor = current.right;
        }

        return delta;
    }

    pub fn checkIntegrity(self: *const Text) !void {
        try self.store.checkIntegrity(self.items.items);

        var previous: ?item_mod.ItemHandle = null;
        var cursor = self.start;
        var visible_len: id.Clock = 0;
        while (cursor) |handle| {
            if (handle >= self.items.items.len) return error.InvalidHandle;
            const current = self.items.items[handle];
            if (current.left != previous) return error.InvalidHandle;
            if (!current.flags.deleted and current.flags.countable) visible_len += current.len;
            previous = handle;
            cursor = current.right;
        }
        if (visible_len != self.length) return error.InvalidHandle;
    }

    pub fn debugItemCount(self: *const Text) usize {
        return self.items.items.len;
    }

    pub fn debugItemLen(self: *const Text, index: usize) id.Clock {
        return self.items.items[index].len;
    }

    pub fn debugItemDeleted(self: *const Text, index: usize) bool {
        return self.items.items[index].flags.deleted;
    }

    pub fn debugFindHandleById(self: *const Text, target: id.Id) TextError!item_mod.ItemHandle {
        return try self.store.findHandleById(self.items.items, target);
    }

    pub fn debugClientState(self: *const Text, client: id.ClientId) id.Clock {
        return self.store.getState(self.items.items, client);
    }

    pub fn debugPendingUpdateCount(self: *const Text) usize {
        return self.pending_updates.items.len;
    }

    pub fn debugEnsureSearchMarkers(self: *Text) TextError!void {
        try self.ensureSearchMarkers();
    }

    pub fn debugSearchMarkersValid(self: *const Text) bool {
        return self.search_markers_valid;
    }

    pub fn debugSearchMarkerCount(self: *const Text) usize {
        return self.search_markers.items.len;
    }

    pub fn debugLiveFormatMarkerCount(self: *const Text, key: []const u8, value: ?[]const u8) usize {
        var count: usize = 0;
        for (self.items.items) |item| {
            if (!item.flags.deleted) {
                switch (item.content) {
                    .string => {},
                    .format => |format_slice| {
                        if (!std.mem.eql(u8, self.attributeKeyBytes(format_slice), key)) continue;
                        if (value) |expected_value| {
                            if (!format_slice.value_is_null and std.mem.eql(u8, self.attributeValueBytes(format_slice), expected_value)) {
                                count += 1;
                            }
                        } else if (format_slice.value_is_null) {
                            count += 1;
                        }
                    },
                }
            }
        }
        return count;
    }

    fn findPosition(self: *Text, index: id.Clock) TextError!Position {
        if (index > self.length) return error.IndexOutOfBounds;

        try self.ensureSearchMarkers();
        const nearest = self.findNearestMarker(index);
        var remaining = nearest.item_offset + (index - nearest.index);
        var left: ?item_mod.ItemHandle = if (nearest.handle) |handle| self.items.items[handle].left else null;
        var cursor = nearest.handle;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            if (!current.flags.deleted and current.flags.countable) {
                if (remaining == 0) {
                    return .{ .left = left, .right = handle };
                }
                if (remaining < current.len) {
                    const right = try self.splitItem(handle, remaining);
                    return .{ .left = handle, .right = right };
                }
                remaining -= current.len;
            }
            left = handle;
            cursor = current.right;
        }

        if (remaining != 0) return error.IndexOutOfBounds;
        return .{ .left = left, .right = null };
    }

    fn ensureSearchMarkers(self: *Text) TextError!void {
        if (self.search_markers_valid) return;

        self.search_markers.clearRetainingCapacity();
        var cursor = self.start;
        var visible_index: id.Clock = 0;
        var next_marker: id.Clock = 0;
        while (cursor) |handle| {
            const current = self.items.items[handle];
            if (!current.flags.deleted and current.flags.countable) {
                while (visible_index + current.len > next_marker) {
                    try self.search_markers.append(self.allocator, .{
                        .index = next_marker,
                        .handle = handle,
                        .item_offset = next_marker - visible_index,
                    });
                    next_marker += search_marker_step;
                }
                visible_index += current.len;
            }
            cursor = current.right;
        }
        self.search_markers_valid = true;
    }

    fn findNearestMarker(self: *const Text, index: id.Clock) struct { index: id.Clock, handle: ?item_mod.ItemHandle, item_offset: id.Clock } {
        var best_index: id.Clock = 0;
        var best_handle: ?item_mod.ItemHandle = self.start;
        var best_item_offset: id.Clock = 0;
        for (self.search_markers.items) |marker| {
            if (marker.index > index) break;
            best_index = marker.index;
            best_handle = marker.handle;
            best_item_offset = marker.item_offset;
        }
        return .{ .index = best_index, .handle = best_handle, .item_offset = best_item_offset };
    }

    fn invalidateSearchMarkers(self: *Text) void {
        self.search_markers_valid = false;
    }

    fn splitItem(self: *Text, handle: item_mod.ItemHandle, offset: id.Clock) TextError!item_mod.ItemHandle {
        if (offset == 0 or offset >= self.items.items[handle].len) return handle;

        const left_snapshot = self.items.items[handle];
        const slice = switch (left_snapshot.content) {
            .string => |string_slice| string_slice,
            .format => return error.UnsupportedContent,
        };
        const full_bytes = self.sliceBytes(slice);
        const byte_offset = try utf.byteOffsetForScalarIndex(full_bytes, offset);
        const right_bytes_len = slice.bytes_len - try intCast(u32, byte_offset);
        const right_len = left_snapshot.len - offset;

        self.items.items[handle].len = offset;
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
            .len = right_len,
            .initial_left_origin_id = self.items.items[handle].lastId(),
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

    fn getItemCleanStart(self: *Text, target: id.Id) TextError!item_mod.ItemHandle {
        const handle = try self.store.findHandleById(self.items.items, target);
        const current = self.items.items[handle];
        if (current.id.clock < target.clock) {
            return try self.splitItem(handle, target.clock - current.id.clock);
        }
        return handle;
    }

    fn getItemCleanEnd(self: *Text, target: id.Id) TextError!item_mod.ItemHandle {
        const handle = try self.store.findHandleById(self.items.items, target);
        const current = self.items.items[handle];
        const offset = target.clock - current.id.clock + 1;
        if (offset < current.len) {
            _ = try self.splitItem(handle, offset);
        }
        return handle;
    }

    fn integrateRemoteItem(self: *Text, remote: RemoteItem) TextError!void {
        const state = self.store.getState(self.items.items, remote.id.client);
        if (remote.id.clock + remote.len <= state) return;
        if (remote.id.clock != state) return error.MissingDependency;

        if (remote.initial_left_origin_id) |origin| {
            if (origin.client != remote.id.client and self.store.getState(self.items.items, origin.client) <= origin.clock) {
                return error.MissingDependency;
            }
        }
        if (remote.initial_right_origin_id) |right_origin| {
            if (right_origin.client != remote.id.client and self.store.getState(self.items.items, right_origin.client) <= right_origin.clock) {
                return error.MissingDependency;
            }
        }

        var left: ?item_mod.ItemHandle = if (remote.initial_left_origin_id) |origin|
            try self.getItemCleanEnd(origin)
        else
            null;
        const right: ?item_mod.ItemHandle = if (remote.initial_right_origin_id) |right_origin|
            try self.getItemCleanStart(right_origin)
        else
            null;

        if ((left == null and (right == null or self.items.items[right.?].left != null)) or
            (left != null and self.items.items[left.?].right != right))
        {
            left = try self.findConflictFreeLeft(left, right, remote);
        }

        const actual_right = if (left) |left_handle| self.items.items[left_handle].right else self.start;
        const content: item_mod.Content = switch (remote.content) {
            .string => |bytes| .{ .string = .{
                .bytes_start = try self.appendBytes(bytes),
                .bytes_len = try intCast(u32, bytes.len),
                .logical_len = remote.len,
            } },
            .format => |format_value| .{ .format = try self.appendAttribute(.{
                .key = format_value.key,
                .value = format_value.value,
            }) },
        };
        const handle = try self.appendItem(.{
            .id = remote.id,
            .len = remote.len,
            .initial_left_origin_id = remote.initial_left_origin_id,
            .initial_right_origin_id = remote.initial_right_origin_id,
            .left = left,
            .right = actual_right,
            .content = content,
            .flags = .{
                .countable = remote.content == .string,
                .deleted = false,
            },
        });

        try self.store.addStruct(self.allocator, self.items.items, handle);
        self.linkInserted(handle, left, actual_right);
        if (remote.content == .string) self.length += remote.len;
    }

    fn markDeletedByIdRange(self: *Text, client: id.ClientId, clock: id.Clock, len_to_delete: id.Clock) TextError!void {
        if (len_to_delete == 0) return;
        const state = self.store.getState(self.items.items, client);
        if (state < clock + len_to_delete) return error.MissingDependency;

        const end_clock = clock + len_to_delete;
        _ = try self.getItemCleanStart(.{ .client = client, .clock = clock });
        if (end_clock < state) {
            _ = try self.getItemCleanStart(.{ .client = client, .clock = end_clock });
        }

        const client_index = self.store.clients.getIndex(client) orelse return error.ClientNotFound;
        const client_structs = self.store.clients.values()[client_index].items.items;
        for (client_structs) |handle| {
            const current = self.items.items[handle];
            if (current.id.clock >= end_clock) break;
            if (current.id.clock + current.len <= clock) continue;

            if (!self.items.items[handle].flags.deleted) {
                self.items.items[handle].flags.deleted = true;
                self.invalidateSearchMarkers();
                if (self.items.items[handle].flags.countable) {
                    self.length -= self.items.items[handle].len;
                }
            }
        }
    }

    fn findConflictFreeLeft(
        self: *Text,
        initial_left: ?item_mod.ItemHandle,
        right: ?item_mod.ItemHandle,
        remote: RemoteItem,
    ) TextError!?item_mod.ItemHandle {
        var left = initial_left;
        var scan = if (left) |left_handle| self.items.items[left_handle].right else self.start;
        var conflicting_items: std.ArrayList(item_mod.ItemHandle) = .empty;
        defer conflicting_items.deinit(self.allocator);
        var items_before_origin: std.ArrayList(item_mod.ItemHandle) = .empty;
        defer items_before_origin.deinit(self.allocator);

        while (scan != null and scan != right) {
            const candidate_handle = scan.?;
            const candidate = self.items.items[candidate_handle];
            try items_before_origin.append(self.allocator, candidate_handle);
            try conflicting_items.append(self.allocator, candidate_handle);

            if (id.idEql(remote.initial_left_origin_id, candidate.initial_left_origin_id)) {
                if (candidate.id.client < remote.id.client) {
                    left = candidate_handle;
                    conflicting_items.clearRetainingCapacity();
                } else if (id.idEql(remote.initial_right_origin_id, candidate.initial_right_origin_id)) {
                    break;
                }
            } else if (candidate.initial_left_origin_id) |candidate_origin| {
                const origin_handle = self.store.findHandleById(self.items.items, candidate_origin) catch null;
                if (origin_handle) |origin| {
                    if (containsHandle(items_before_origin.items, origin)) {
                        if (!containsHandle(conflicting_items.items, origin)) {
                            left = candidate_handle;
                            conflicting_items.clearRetainingCapacity();
                        }
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            } else {
                break;
            }
            scan = candidate.right;
        }

        return left;
    }

    fn cleanupFormatting(self: *Text) TextError!void {
        var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
        defer active_attrs.deinit(self.allocator);

        var cursor = self.start;
        while (cursor) |handle| {
            if (!self.items.items[handle].flags.deleted) {
                switch (self.items.items[handle].content) {
                    .string => {},
                    .format => |format_slice| {
                        if (formatIsRedundant(self, active_attrs.items, format_slice)) {
                            self.items.items[handle].flags.deleted = true;
                            self.invalidateSearchMarkers();
                        } else {
                            try updateActiveAttrs(self, self.allocator, &active_attrs, format_slice);
                        }
                    },
                }
            }
            cursor = self.items.items[handle].right;
        }
    }

    fn retryPendingUpdates(self: *Text) TextError!void {
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

    fn applyUpdateOnce(self: *Text, update: []const u8) TextError!void {
        var dec = encoding.Decoder.init(update);
        const magic = try dec.readRaw(update_magic.len);
        if (!std.mem.eql(u8, magic, update_magic)) return error.InvalidUpdate;

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
                const left_origin = if ((info & 1) != 0) try readId(&dec) else null;
                const right_origin = if ((info & 2) != 0) try readId(&dec) else null;
                const content_tag = try dec.readByte();
                const content: RemoteContent = switch (content_tag) {
                    content_string_tag => blk: {
                        const string_bytes = try dec.readBytes();
                        const logical_len = try utf.scalarCount(string_bytes);
                        if (logical_len != len_value) return error.InvalidUpdate;
                        break :blk .{ .string = string_bytes };
                    },
                    content_format_tag => blk: {
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
                try self.integrateRemoteItem(.{
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
                try self.markDeletedByIdRange(client, clock, delete_len);
            }
        }
        try dec.expectEnd();
    }

    fn writeStructs(self: *const Text, enc: *encoding.Encoder, target_state: *const StateVector) TextError!void {
        var changed_clients: usize = 0;
        for (self.store.clients.keys(), self.store.clients.values()) |client, client_structs| {
            const target_clock = target_state.get(client) orelse 0;
            for (client_structs.items.items) |handle| {
                const current = self.items.items[handle];
                if (current.id.clock + current.len > target_clock) {
                    changed_clients += 1;
                    break;
                }
            }
        }

        try enc.writeVarU64(changed_clients);
        for (self.store.clients.keys(), self.store.clients.values()) |client, client_structs| {
            const target_clock = target_state.get(client) orelse 0;
            var item_count: usize = 0;
            for (client_structs.items.items) |handle| {
                const current = self.items.items[handle];
                if (current.id.clock + current.len > target_clock) item_count += 1;
            }
            if (item_count == 0) continue;

            try enc.writeVarU64(client);
            try enc.writeVarU64(item_count);
            for (client_structs.items.items) |handle| {
                const current = self.items.items[handle];
                if (current.id.clock + current.len <= target_clock) continue;
                const offset = if (target_clock > current.id.clock) target_clock - current.id.clock else 0;
                const write_id: id.Id = .{
                    .client = current.id.client,
                    .clock = current.id.clock + offset,
                };
                const write_len = current.len - offset;
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
                        const item_bytes = self.sliceBytes(slice);
                        const byte_offset = try utf.byteOffsetForScalarIndex(item_bytes, offset);
                        try enc.writeBytes(item_bytes[byte_offset..]);
                    },
                    .format => |format_slice| {
                        if (offset != 0) return error.InvalidUpdate;
                        try enc.writeByte(content_format_tag);
                        try enc.writeBytes(self.attributeKeyBytes(format_slice));
                        try enc.writeByte(if (format_slice.value_is_null) 1 else 0);
                        if (!format_slice.value_is_null) {
                            try enc.writeBytes(self.attributeValueBytes(format_slice));
                        }
                    },
                }
            }
        }
    }

    fn writeDeleteSet(self: *const Text, enc: *encoding.Encoder) TextError!void {
        var ds: delete_set_mod.DeleteSet = .{};
        defer ds.deinit(self.allocator);

        for (self.store.clients.keys(), self.store.clients.values()) |client, client_structs| {
            var active_start: ?id.Clock = null;
            var active_len: id.Clock = 0;
            for (client_structs.items.items) |handle| {
                const current = self.items.items[handle];
                if (current.flags.deleted) {
                    if (active_start == null) active_start = current.id.clock;
                    active_len += current.len;
                } else if (active_start) |start_clock| {
                    try ds.add(self.allocator, client, start_clock, active_len);
                    active_start = null;
                    active_len = 0;
                }
            }
            if (active_start) |start_clock| {
                try ds.add(self.allocator, client, start_clock, active_len);
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

    fn linkInserted(
        self: *Text,
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

    fn appendItem(self: *Text, new_item: item_mod.Item) TextError!item_mod.ItemHandle {
        const handle = try intCast(item_mod.ItemHandle, self.items.items.len);
        try self.items.append(self.allocator, new_item);
        return handle;
    }

    fn appendBytes(self: *Text, source: []const u8) TextError!u32 {
        const start = try intCast(u32, self.bytes.items.len);
        try self.bytes.appendSlice(self.allocator, source);
        return start;
    }

    fn appendAttribute(self: *Text, attribute: attrs.Attribute) TextError!item_mod.AttributeSlice {
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

    fn sliceBytes(self: *const Text, slice: item_mod.TextSlice) []const u8 {
        const start: usize = slice.bytes_start;
        return self.bytes.items[start..][0..slice.bytes_len];
    }

    fn attributeKeyBytes(self: *const Text, slice: item_mod.AttributeSlice) []const u8 {
        const start: usize = slice.key_start;
        return self.bytes.items[start..][0..slice.key_len];
    }

    fn attributeValueBytes(self: *const Text, slice: item_mod.AttributeSlice) []const u8 {
        const start: usize = slice.value_start;
        return self.bytes.items[start..][0..slice.value_len];
    }
};

fn intCast(comptime T: type, value: anytype) error{TextTooLarge}!T {
    return std.math.cast(T, value) orelse error.TextTooLarge;
}

fn writeId(enc: *encoding.Encoder, value: id.Id) TextError!void {
    try enc.writeVarU64(value.client);
    try enc.writeVarU64(value.clock);
}

fn readId(dec: *encoding.Decoder) TextError!id.Id {
    return .{
        .client = try dec.readVarU64(),
        .clock = try dec.readVarU64(),
    };
}

fn decodeStateVector(allocator: std.mem.Allocator, encoded: []const u8) TextError!StateVector {
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

fn updateActiveAttrs(
    text: *const Text,
    allocator: std.mem.Allocator,
    active_attrs: *std.ArrayList(attrs.Attribute),
    format_slice: item_mod.AttributeSlice,
) TextError!void {
    const key = text.attributeKeyBytes(format_slice);
    for (active_attrs.items, 0..) |attribute, index| {
        if (std.mem.eql(u8, attribute.key, key)) {
            if (format_slice.value_is_null) {
                _ = active_attrs.orderedRemove(index);
            } else {
                active_attrs.items[index].value = .{ .string = text.attributeValueBytes(format_slice) };
            }
            return;
        }
    }
    if (!format_slice.value_is_null) {
        try active_attrs.append(allocator, .{
            .key = key,
            .value = .{ .string = text.attributeValueBytes(format_slice) },
        });
    }
}

fn formatIsRedundant(
    text: *const Text,
    active_attrs: []const attrs.Attribute,
    format_slice: item_mod.AttributeSlice,
) bool {
    const key = text.attributeKeyBytes(format_slice);
    for (active_attrs) |attribute| {
        if (std.mem.eql(u8, attribute.key, key)) {
            if (format_slice.value_is_null) return false;
            return switch (attribute.value) {
                .null => false,
                .string => |value| std.mem.eql(u8, value, text.attributeValueBytes(format_slice)),
            };
        }
    }
    return format_slice.value_is_null;
}

fn containsHandle(handles: []const item_mod.ItemHandle, needle: item_mod.ItemHandle) bool {
    for (handles) |handle| {
        if (handle == needle) return true;
    }
    return false;
}

fn copyAttributes(allocator: std.mem.Allocator, source: []const attrs.Attribute) TextError![]attrs.Attribute {
    if (source.len == 0) return &.{};
    const copied = try allocator.alloc(attrs.Attribute, source.len);
    errdefer allocator.free(copied);

    var initialized: usize = 0;
    errdefer {
        for (copied[0..initialized]) |attribute| {
            allocator.free(attribute.key);
            switch (attribute.value) {
                .null => {},
                .string => |value| allocator.free(value),
            }
        }
    }

    for (source, 0..) |attribute, index| {
        copied[index].key = try allocator.dupe(u8, attribute.key);
        copied[index].value = switch (attribute.value) {
            .null => .null,
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
        };
        initialized += 1;
    }
    return copied;
}

fn freeAttributes(allocator: std.mem.Allocator, attributes: []attrs.Attribute) void {
    if (attributes.len == 0) return;
    for (attributes) |attribute| {
        allocator.free(attribute.key);
        switch (attribute.value) {
            .null => {},
            .string => |value| allocator.free(value),
        }
    }
    allocator.free(attributes);
}
