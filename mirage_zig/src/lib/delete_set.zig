const std = @import("std");
const id = @import("id.zig");

pub const DeleteItem = struct {
    clock: id.Clock,
    len: id.Clock,
};

pub const DeleteSet = struct {
    clients: std.array_hash_map.Auto(id.ClientId, std.ArrayList(DeleteItem)) = .empty,

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

        try addMerged(allocator, result.value_ptr, .{ .clock = clock, .len = len });
    }

    pub fn sortAndMerge(self: *DeleteSet) void {
        for (self.clients.values()) |*items| {
            sortAndMergeClient(items);
        }
    }

    pub fn byteLen(self: *const DeleteSet) usize {
        var total = self.clients.count() * (@sizeOf(id.ClientId) + @sizeOf(std.ArrayList(DeleteItem)));
        for (self.clients.values()) |items| {
            total += items.items.len * @sizeOf(DeleteItem);
        }
        return total;
    }
};

fn addMerged(allocator: std.mem.Allocator, items: *std.ArrayList(DeleteItem), next: DeleteItem) !void {
    var start = next.clock;
    var end = next.clock + next.len;

    var index: usize = 0;
    while (index < items.items.len) : (index += 1) {
        const current = items.items[index];
        if (current.clock + current.len >= start) break;
    }

    var merged_until = index;
    while (merged_until < items.items.len) : (merged_until += 1) {
        const current = items.items[merged_until];
        if (current.clock > end) break;
        start = @min(start, current.clock);
        end = @max(end, current.clock + current.len);
    }

    const merged = DeleteItem{ .clock = start, .len = end - start };
    if (merged_until == index) {
        try items.insert(allocator, index, merged);
        return;
    }

    items.items[index] = merged;
    var remove_count = merged_until - index - 1;
    while (remove_count > 0) : (remove_count -= 1) {
        _ = items.orderedRemove(index + 1);
    }
}

fn sortAndMergeClient(items: *std.ArrayList(DeleteItem)) void {
    std.mem.sort(DeleteItem, items.items, {}, lessThan);
    if (items.items.len == 0) {
        return;
    }

    var merged_len: usize = 1;
    for (items.items[1..]) |next| {
        var last = &items.items[merged_len - 1];
        const last_end = last.clock + last.len;
        const next_end = next.clock + next.len;
        const is_overlap = last_end >= next.clock;
        if (is_overlap) {
            const should_increase_len = next_end > last_end;
            if (should_increase_len) {
                last.len = next_end - last.clock;
            }
        } else {
            items.items[merged_len] = next;
            merged_len += 1;
        }
    }
    items.shrinkRetainingCapacity(merged_len);
}

fn lessThan(_: void, a: DeleteItem, b: DeleteItem) bool {
    return a.clock < b.clock;
}

const expectEqual = std.testing.expectEqual;

test "DeleteSet sortAndMerge" {
    const allocator = std.testing.allocator;
    var ds = DeleteSet{};
    defer ds.deinit(allocator);

    // [0..3] [2..9] [10..12]
    try ds.add(allocator, 1, 0, 3);
    try ds.add(allocator, 1, 2, 7);
    try ds.add(allocator, 1, 10, 2);

    ds.sortAndMerge();
    // [0..9] [10..12]

    const deletes = ds.clients.get(1) orelse unreachable;
    try expectEqual(deletes.items.len, 2);
    try expectEqual(deletes.items[0].clock, 0);
    try expectEqual(deletes.items[0].len, 9);
    try expectEqual(deletes.items[1].clock, 10);
    try expectEqual(deletes.items[1].len, 2);
}

test "DeleteSet sortAndMerge one element" {
    const allocator = std.testing.allocator;
    var ds = DeleteSet{};
    defer ds.deinit(allocator);

    // [0..3]
    try ds.add(allocator, 1, 0, 3);

    ds.sortAndMerge();
    // [0..3]

    const deletes = ds.clients.get(1) orelse unreachable;
    try expectEqual(deletes.items.len, 1);
    try expectEqual(deletes.items[0].clock, 0);
    try expectEqual(deletes.items[0].len, 3);
}

test "DeleteSet sortAndMerge empty" {
    var ds = DeleteSet{};
    ds.sortAndMerge();
}

test "DeleteSet sortAndMerge all" {
    const allocator = std.testing.allocator;
    var ds = DeleteSet{};
    defer ds.deinit(allocator);

    // [0..3] [3..5] [5..10]
    try ds.add(allocator, 1, 0, 3);
    try ds.add(allocator, 1, 3, 2);
    try ds.add(allocator, 1, 5, 5);

    ds.sortAndMerge();
    // [0..10]

    const deletes = ds.clients.get(1) orelse unreachable;
    try expectEqual(deletes.items.len, 1);
    try expectEqual(deletes.items[0].clock, 0);
    try expectEqual(deletes.items[0].len, 10);
}

test "DeleteSet add keeps ranges sorted and merged" {
    const allocator = std.testing.allocator;
    var ds = DeleteSet{};
    defer ds.deinit(allocator);

    try ds.add(allocator, 1, 10, 2);
    try ds.add(allocator, 1, 0, 3);
    try ds.add(allocator, 1, 5, 2);
    try ds.add(allocator, 1, 3, 2);
    try ds.add(allocator, 1, 12, 1);

    const deletes = ds.clients.get(1) orelse unreachable;
    try expectEqual(deletes.items.len, 2);
    try expectEqual(deletes.items[0].clock, 0);
    try expectEqual(deletes.items[0].len, 7);
    try expectEqual(deletes.items[1].clock, 10);
    try expectEqual(deletes.items[1].len, 3);
}
