const std = @import("std");
const attrs = @import("attrs.zig");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const text_mod = @import("text.zig");

pub const RemoteItem = struct {
    id: id.Id,
    len: id.Clock,
    initial_left_origin_id: ?id.Id,
    initial_right_origin_id: ?id.Id,
    content: RemoteContent,
};

pub const RemoteContent = union(enum) {
    string: []const u8,
    format: RemoteFormat,
};

pub const RemoteFormat = struct {
    key: []const u8,
    value: attrs.AttributeValue,
};

pub fn item(text: *text_mod.TextImpl, remote: RemoteItem) !void {
    const state = text.store.getState(text.items.items, remote.id.client);
    if (remote.id.clock + remote.len <= state) return;
    if (remote.id.clock != state) return error.MissingDependency;

    if (remote.initial_left_origin_id) |origin| {
        if (origin.client != remote.id.client and text.store.getState(text.items.items, origin.client) <= origin.clock) {
            return error.MissingDependency;
        }
    }
    if (remote.initial_right_origin_id) |right_origin| {
        if (right_origin.client != remote.id.client and text.store.getState(text.items.items, right_origin.client) <= right_origin.clock) {
            return error.MissingDependency;
        }
    }

    var left: ?item_mod.ItemHandle = if (remote.initial_left_origin_id) |origin|
        try text.getItemCleanEnd(origin)
    else
        null;
    const right: ?item_mod.ItemHandle = if (remote.initial_right_origin_id) |right_origin|
        try text.getItemCleanStart(right_origin)
    else
        null;

    if ((left == null and (right == null or text.items.items[right.?].left != null)) or
        (left != null and text.items.items[left.?].right != right))
    {
        left = try findConflictFreeLeft(text, left, right, remote);
    }

    const actual_right = if (left) |left_handle| text.items.items[left_handle].right else text.start;
    const content: item_mod.Content = switch (remote.content) {
        .string => |bytes| .{ .string = .{
            .bytes_start = try text.appendBytes(bytes),
            .bytes_len = try intCast(u32, bytes.len),
            .logical_len = remote.len,
        } },
        .format => |format_value| .{ .format = try text.appendAttribute(.{
            .key = format_value.key,
            .value = format_value.value,
        }) },
    };
    const handle = try text.appendItem(.{
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

    try text.store.addStruct(text.allocator, text.items.items, handle);
    text.linkInserted(handle, left, actual_right);
    if (remote.content == .string) text.length += remote.len;
}

pub fn deletedRange(text: *text_mod.TextImpl, client: id.ClientId, clock: id.Clock, len_to_delete: id.Clock) !void {
    if (len_to_delete == 0) return;
    const state = text.store.getState(text.items.items, client);
    if (state < clock + len_to_delete) return error.MissingDependency;

    const end_clock = clock + len_to_delete;
    _ = try text.getItemCleanStart(.{ .client = client, .clock = clock });
    if (end_clock < state) {
        _ = try text.getItemCleanStart(.{ .client = client, .clock = end_clock });
    }

    const client_index = text.store.clients.getIndex(client) orelse return error.ClientNotFound;
    const client_structs = text.store.clients.values()[client_index].items.items;
    for (client_structs) |handle| {
        const current = text.items.items[handle];
        if (current.id.clock >= end_clock) break;
        if (current.id.clock + current.len <= clock) continue;

        if (!text.items.items[handle].flags.deleted) {
            text.items.items[handle].flags.deleted = true;
            text.invalidateSearchMarkers();
            if (text.items.items[handle].flags.countable) {
                text.length -= text.items.items[handle].len;
            }
        }
    }
}

fn findConflictFreeLeft(
    text: *text_mod.TextImpl,
    initial_left: ?item_mod.ItemHandle,
    right: ?item_mod.ItemHandle,
    remote: RemoteItem,
) !?item_mod.ItemHandle {
    var left = initial_left;
    var scan = if (left) |left_handle| text.items.items[left_handle].right else text.start;
    var conflicting_items: std.ArrayList(item_mod.ItemHandle) = .empty;
    defer conflicting_items.deinit(text.allocator);
    var items_before_origin: std.ArrayList(item_mod.ItemHandle) = .empty;
    defer items_before_origin.deinit(text.allocator);

    while (scan != null and scan != right) {
        const candidate_handle = scan.?;
        const candidate = text.items.items[candidate_handle];
        try items_before_origin.append(text.allocator, candidate_handle);
        try conflicting_items.append(text.allocator, candidate_handle);

        if (id.check_if_id_eql(remote.initial_left_origin_id, candidate.initial_left_origin_id)) {
            if (candidate.id.client < remote.id.client) {
                left = candidate_handle;
                conflicting_items.clearRetainingCapacity();
            } else if (id.check_if_id_eql(remote.initial_right_origin_id, candidate.initial_right_origin_id)) {
                break;
            }
        } else if (candidate.initial_left_origin_id) |candidate_origin| {
            const origin_handle = text.store.findHandleById(text.items.items, candidate_origin) catch null;
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

fn containsHandle(handles: []const item_mod.ItemHandle, needle: item_mod.ItemHandle) bool {
    for (handles) |handle| {
        if (handle == needle) return true;
    }
    return false;
}

fn intCast(comptime T: type, value: anytype) error{TextTooLarge}!T {
    return std.math.cast(T, value) orelse error.TextTooLarge;
}
