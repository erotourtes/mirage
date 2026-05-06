const std = @import("std");
const id = @import("id.zig");

pub const DeleteItem = struct {
    clock: id.Clock,
    len: id.Clock,
};

pub const DeleteSet = struct {
    clients: std.AutoArrayHashMapUnmanaged(id.ClientId, std.ArrayList(DeleteItem)) = .empty,

    pub fn deinit(self: *DeleteSet, allocator: std.mem.Allocator) void {
        for (self.clients.values()) |*items| {
            items.deinit(allocator);
        }
        self.clients.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(
        self: *DeleteSet,
        allocator: std.mem.Allocator,
        client: id.ClientId,
        clock: id.Clock,
        len: id.Clock,
    ) !void {
        if (len == 0) return;
        const result = try self.clients.getOrPut(allocator, client);
        if (!result.found_existing) result.value_ptr.* = .empty;
        try result.value_ptr.append(allocator, .{ .clock = clock, .len = len });
    }

    pub fn sortAndMerge(self: *DeleteSet) void {
        for (self.clients.values()) |*items| {
            std.mem.sort(DeleteItem, items.items, {}, lessThan);
            if (items.items.len == 0) continue;

            var write_index: usize = 1;
            for (items.items[1..]) |next| {
                var last = &items.items[write_index - 1];
                const last_end = last.clock + last.len;
                const next_end = next.clock + next.len;
                if (last_end >= next.clock) {
                    if (next_end > last_end) last.len = next_end - last.clock;
                } else {
                    items.items[write_index] = next;
                    write_index += 1;
                }
            }
            items.shrinkRetainingCapacity(write_index);
        }
    }
};

fn lessThan(_: void, a: DeleteItem, b: DeleteItem) bool {
    return a.clock < b.clock;
}
