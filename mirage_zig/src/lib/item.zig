const id = @import("id.zig");

pub const ItemHandle = u32;

pub const ItemFlags = packed struct {
    countable: bool,
    deleted: bool,
    keep: bool = false,
};

pub const TextSlice = struct {
    bytes_start: u32,
    bytes_len: u32,
    logical_len: id.Clock,
};

pub const AttributeSlice = struct {
    key_start: u32,
    key_len: u32,
    value_start: u32 = 0,
    value_len: u32 = 0,
    value_is_null: bool,
};

pub const Content = union(enum) {
    string: TextSlice,
    format: AttributeSlice,

    pub fn get_clock_len(self: Content) id.Clock {
        return switch (self) {
            .string => |slice| slice.logical_len,
            .format => 1,
        };
    }
};

pub const Item = struct {
    id: id.Id,

    initial_left_origin_id: ?id.Id,
    initial_right_origin_id: ?id.Id,

    /// The index of the left item in the linked list
    left: ?ItemHandle,
    /// The index of the right item in the linked list
    right: ?ItemHandle,

    content: Content,

    flags: ItemFlags,

    /// Returns how many Clock ticks this item occupies
    /// For text content, it's equal to number of visible characters
    /// For format content, it's always 1
    ///
    /// If an item has it as `3`, it means that it owns these ids
    /// - {client, clock + 0}
    /// - {client, clock + 1}
    /// - {client, clock + 2}
    pub fn getClockLen(self: Item) id.Clock {
        return self.content.get_clock_len();
    }

    pub fn getLastId(self: Item) id.Id {
        const clock_len = self.getClockLen();
        return .{
            .client = self.id.client,
            .clock = self.id.clock + clock_len - 1,
        };
    }
};

const expectEqual = @import("std").testing.expectEqual;

test "Item.get_last_id returns the correct last id for string content" {
    var item: Item = undefined;
    item.id = .{ .client = 1, .clock = 2 };
    item.content = .{ .string = .{
        .bytes_start = 0,
        .bytes_len = 3,
        .logical_len = 3,
    } };

    const last_id = item.getLastId();

    try expectEqual(1, last_id.client);
    try expectEqual(4, last_id.clock);
}
