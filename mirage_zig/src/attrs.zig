const std = @import("std");

pub const AttributeValue = union(enum) {
    null,
    string: []const u8,
};

pub const Attribute = struct {
    key: []const u8,
    value: AttributeValue,
};

pub const DeltaOp = struct {
    insert: []u8,
    attributes: []Attribute = &.{},

    pub fn deinit(self: DeltaOp, allocator: std.mem.Allocator) void {
        allocator.free(self.insert);
        for (self.attributes) |attribute| {
            allocator.free(attribute.key);
            switch (attribute.value) {
                .null => {},
                .string => |value| allocator.free(value),
            }
        }
        allocator.free(self.attributes);
    }
};

pub const Delta = struct {
    ops: std.ArrayList(DeltaOp) = .empty,

    pub fn deinit(self: *Delta, allocator: std.mem.Allocator) void {
        for (self.ops.items) |op| {
            op.deinit(allocator);
        }
        self.ops.deinit(allocator);
        self.* = undefined;
    }
};
