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

    pub fn logicalLen(self: Content) id.Clock {
        return switch (self) {
            .string => |slice| slice.logical_len,
            .format => 1,
        };
    }
};

pub const Item = struct {
    id: id.Id,
    len: id.Clock,

    initial_left_origin_id: ?id.Id,
    initial_right_origin_id: ?id.Id,

    left: ?ItemHandle,
    right: ?ItemHandle,

    content: Content,

    flags: ItemFlags,

    pub fn lastId(self: Item) id.Id {
        return .{
            .client = self.id.client,
            .clock = self.id.clock + self.len - 1,
        };
    }
};
