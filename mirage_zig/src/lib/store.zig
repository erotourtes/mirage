const std = @import("std");
const id = @import("id.zig");
const item = @import("item.zig");

pub const StoreError = error{
    ClockGap,
    ClientNotFound,
    StructNotFound,
};

pub const ClientStructs = struct {
    items: std.ArrayList(item.ItemHandle) = .empty,

    pub fn deinit(self: *ClientStructs, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }
};

pub const StructStore = struct {
    clients: std.AutoArrayHashMapUnmanaged(id.ClientId, ClientStructs) = .empty,

    pub fn deinit(self: *StructStore, allocator: std.mem.Allocator) void {
        for (self.clients.values()) |*client_structs| {
            client_structs.deinit(allocator);
        }
        self.clients.deinit(allocator);
        self.* = undefined;
    }

    pub fn getState(self: *const StructStore, items: []const item.Item, client: id.ClientId) id.Clock {
        const index = self.clients.getIndex(client) orelse return 0;
        const structs = self.clients.values()[index].items.items;
        if (structs.len == 0) return 0;
        const last = items[structs[structs.len - 1]];
        return last.id.clock + last.len;
    }

    pub fn addStruct(
        self: *StructStore,
        allocator: std.mem.Allocator,
        items: []const item.Item,
        handle: item.ItemHandle,
    ) !void {
        const new_item = items[handle];
        const result = try self.clients.getOrPut(allocator, new_item.id.client);
        if (!result.found_existing) {
            if (new_item.id.clock != 0) return error.ClockGap;
            result.value_ptr.* = .{};
        } else if (result.value_ptr.items.items.len > 0) {
            const structs = result.value_ptr.items.items;
            const last = items[structs[structs.len - 1]];
            if (last.id.clock + last.len != new_item.id.clock) return error.ClockGap;
        }

        try result.value_ptr.items.append(allocator, handle);
    }

    pub fn insertStructAfter(
        self: *StructStore,
        allocator: std.mem.Allocator,
        items: []const item.Item,
        left_handle: item.ItemHandle,
        new_handle: item.ItemHandle,
    ) !void {
        const new_item = items[new_handle];
        const index = self.clients.getIndex(new_item.id.client) orelse return error.ClientNotFound;
        var structs = &self.clients.values()[index].items;
        const insert_index = (try findHandleIndex(structs.items, left_handle)) + 1;
        try structs.insert(allocator, insert_index, new_handle);
    }

    pub fn findHandleById(
        self: *const StructStore,
        items: []const item.Item,
        target: id.Id,
    ) StoreError!item.ItemHandle {
        const index = self.clients.getIndex(target.client) orelse return error.ClientNotFound;
        const structs = self.clients.values()[index].items.items;
        const struct_index = try findIndexByClock(items, structs, target.clock);
        return structs[struct_index];
    }

    pub fn checkIntegrity(self: *const StructStore, items: []const item.Item) StoreError!void {
        for (self.clients.values()) |client_structs| {
            const structs = client_structs.items.items;
            if (structs.len == 0) continue;
            for (structs[1..], 1..) |handle, index| {
                const left = items[structs[index - 1]];
                const right = items[handle];
                if (left.id.clock + left.len != right.id.clock) return error.ClockGap;
            }
        }
    }
};

fn findHandleIndex(handles: []const item.ItemHandle, target: item.ItemHandle) StoreError!usize {
    for (handles, 0..) |handle, index| {
        if (handle == target) return index;
    }
    return error.StructNotFound;
}

fn findIndexByClock(
    items: []const item.Item,
    handles: []const item.ItemHandle,
    clock: id.Clock,
) StoreError!usize {
    if (handles.len == 0) return error.StructNotFound;

    var left: usize = 0;
    var right: usize = handles.len - 1;
    while (left <= right) {
        const mid = left + (right - left) / 2;
        const candidate = items[handles[mid]];
        if (clock < candidate.id.clock) {
            if (mid == 0) break;
            right = mid - 1;
        } else if (clock >= candidate.id.clock + candidate.len) {
            left = mid + 1;
        } else {
            return mid;
        }
    }
    return error.StructNotFound;
}
