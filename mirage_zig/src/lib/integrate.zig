const std = @import("std");
const attrs = @import("attrs.zig");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const text_mod = @import("text/impl.zig");

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

pub const RemoteDeleteRange = struct {
    client: id.ClientId,
    clock: id.Clock,
    len: id.Clock,
};

pub fn item(text: *text_mod.TextImpl, remote: RemoteItem) !void {
    const next_expected_clock = text.store.getState(text.items.items, remote.id.client);
    if (remote.id.clock + remote.len <= next_expected_clock) return;
    if (remote.id.clock != next_expected_clock) return error.MissingDependency;

    if (remote.initial_left_origin_id) |remote_origin| {
        const is_missing_dependency = brk: {
            // If the origin is from the same client
            // we already checked for remote.id.clock != state
            if (remote_origin.client == remote.id.client)
                break :brk false;
            const next_expected_origin_clock = text.store.getState(text.items.items, remote_origin.client);
            break :brk next_expected_origin_clock <= remote_origin.clock;
        };
        if (is_missing_dependency) {
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

    const is_conflicting = brk: {
        const is_inserting_at_beginning = left == null;
        if (is_inserting_at_beginning) {
            if (right == null)
                // no origin boundaries; resolve against existing items
                break :brk true;
            if (text.items.items[right.?].left != null)
                // there is already something before `right`
                break :brk true;
            break :brk false;
        }

        // insert after `left` before `right`.
        // if there is something between `left` and `right`, it must be a conflict
        break :brk text.items.items[left.?].right != right;
    };
    if (is_conflicting) {
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

pub fn deletedRange(text: *text_mod.TextImpl, remote: RemoteDeleteRange) !void {
    if (remote.len == 0) return;
    const state = text.store.getState(text.items.items, remote.client);
    if (state < remote.clock + remote.len) return error.MissingDependency;

    const end_clock = remote.clock + remote.len;
    _ = try text.getItemCleanStart(.{ .client = remote.client, .clock = remote.clock });
    if (end_clock < state) {
        _ = try text.getItemCleanStart(.{ .client = remote.client, .clock = end_clock });
    }

    const client_index = text.store.clients.getIndex(remote.client) orelse return error.ClientNotFound;
    const client_structs = text.store.clients.values()[client_index].items.items;
    for (client_structs) |handle| {
        const current = text.items.items[handle];
        if (current.id.clock >= end_clock) break;
        if (current.id.clock + current.getClockLen() <= remote.clock) continue;

        if (!text.items.items[handle].flags.deleted) {
            text.items.items[handle].flags.deleted = true;
            text.invalidateSearchMarkers();
            if (text.items.items[handle].flags.countable) {
                text.length -= text.items.items[handle].getClockLen();
            }
        }
    }
}

/// `remote` wants to insert between `initial_left` and `right`, but
/// there are some items in this gap.
///
/// Returns the handle of the item's actual left neighbor deterministically.
///
/// initial_left | A | B | C | right
///                   ^ remote wants to insert here
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

        if (id.checkIfIdEql(remote.initial_left_origin_id, candidate.initial_left_origin_id)) {
            // deterministic client ID tiebreak
            const should_remote_go_after = candidate.id.client < remote.id.client;
            if (should_remote_go_after) {
                left = candidate_handle;
                conflicting_items.clearRetainingCapacity();
            } else if (id.checkIfIdEql(remote.initial_right_origin_id, candidate.initial_right_origin_id)) {
                // remote goes before candidate
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
