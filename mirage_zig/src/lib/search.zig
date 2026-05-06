const std = @import("std");
const id = @import("id.zig");
const item_mod = @import("item.zig");
const text_mod = @import("text/impl.zig");

const marker_step: id.Clock = 32;

const Marker = struct {
    index: id.Clock,
    handle: item_mod.ItemHandle,
    item_offset: id.Clock,
};

pub const Nearest = struct {
    index: id.Clock,
    handle: ?item_mod.ItemHandle,
    item_offset: id.Clock,
};

pub const Cache = struct {
    markers: std.ArrayList(Marker) = .empty,
    valid: bool = false,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        self.markers.deinit(allocator);
        self.* = undefined;
    }

    pub fn invalidate(self: *Cache) void {
        self.valid = false;
    }

    pub fn isValid(self: *const Cache) bool {
        return self.valid;
    }

    pub fn count(self: *const Cache) usize {
        return self.markers.items.len;
    }

    pub fn ensure(self: *Cache, text: *const text_mod.TextImpl) !void {
        if (self.valid) return;

        self.markers.clearRetainingCapacity();
        var cursor = text.start;
        var visible_index: id.Clock = 0;
        var next_marker: id.Clock = 0;
        while (cursor) |handle| {
            const current = text.items.items[handle];
            if (!current.flags.deleted and current.flags.countable) {
                const current_len = current.getClockLen();
                while (visible_index + current_len > next_marker) {
                    try self.markers.append(text.allocator, .{
                        .index = next_marker,
                        .handle = handle,
                        .item_offset = next_marker - visible_index,
                    });
                    next_marker += marker_step;
                }
                visible_index += current_len;
            }
            cursor = current.right;
        }
        self.valid = true;
    }

    pub fn nearest(self: *const Cache, text: *const text_mod.TextImpl, index: id.Clock) Nearest {
        var best_index: id.Clock = 0;
        var best_handle: ?item_mod.ItemHandle = text.start;
        var best_item_offset: id.Clock = 0;
        for (self.markers.items) |marker| {
            if (marker.index > index) break;
            best_index = marker.index;
            best_handle = marker.handle;
            best_item_offset = marker.item_offset;
        }
        return .{
            .index = best_index,
            .handle = best_handle,
            .item_offset = best_item_offset,
        };
    }
};
