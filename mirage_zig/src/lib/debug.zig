const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const store_mod = @import("store.zig");

pub const View = struct {
    store: *const store_mod.StructStore,
    items: []const item_mod.Item,
    bytes: []const u8,
    start: ?item_mod.ItemHandle,
    length: id.TextLen,
    pending_update_count: usize,
    search_markers_valid: bool,
    search_marker_count: usize,
};

pub fn checkIntegrity(view: View) !void {
    try view.store.checkIntegrity(view.items);

    var previous: ?item_mod.ItemHandle = null;
    var cursor = view.start;
    var visible_len: id.TextLen = 0;
    while (cursor) |handle| {
        if (handle >= view.items.len) return error.InvalidHandle;
        const current = view.items[handle];
        if (current.left != previous) return error.InvalidHandle;
        if (!current.flags.deleted and current.flags.countable) visible_len += current.getClockLen();
        previous = handle;
        cursor = current.right;
    }
    if (visible_len != view.length) return error.InvalidHandle;
}

pub fn itemCount(view: View) usize {
    return view.items.len;
}

pub fn itemLen(view: View, index: usize) id.Clock {
    return view.items[index].getClockLen();
}

pub fn itemDeleted(view: View, index: usize) bool {
    return view.items[index].flags.deleted;
}

pub fn findHandleById(view: View, target: id.Id) !item_mod.ItemHandle {
    return try view.store.findHandleById(view.items, target);
}

pub fn clientState(view: View, client: id.ClientId) id.Clock {
    return view.store.getState(view.items, client);
}

pub fn pendingUpdateCount(view: View) usize {
    return view.pending_update_count;
}

pub fn searchMarkersValid(view: View) bool {
    return view.search_markers_valid;
}

pub fn searchMarkerCount(view: View) usize {
    return view.search_marker_count;
}

pub fn liveFormatMarkerCount(view: View, key: []const u8, value: ?[]const u8) usize {
    var count: usize = 0;
    for (view.items) |item| {
        if (!item.flags.deleted) {
            switch (item.content) {
                .string => {},
                .format => |format_slice| {
                    if (!std.mem.eql(u8, attributeKeyBytes(view, format_slice), key)) continue;
                    if (value) |expected_value| {
                        if (!format_slice.value_is_null and std.mem.eql(u8, attributeValueBytes(view, format_slice), expected_value)) {
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

fn attributeKeyBytes(view: View, slice: item_mod.AttributeSlice) []const u8 {
    const start: usize = slice.key_start;
    return view.bytes[start..][0..slice.key_len];
}

fn attributeValueBytes(view: View, slice: item_mod.AttributeSlice) []const u8 {
    const start: usize = slice.value_start;
    return view.bytes[start..][0..slice.value_len];
}
