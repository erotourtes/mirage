const std = @import("std");

pub const AttributeValue = union(enum) {
    /// Clear the attribute for the formatted range.
    null,
    /// Set the attribute to an opaque UTF-8 string value.
    string: []const u8,
};

pub const Attribute = struct {
    /// Attribute key, such as "bold" or "color".
    key: []const u8,
    /// Attribute value. Mirage intentionally supports only null and strings.
    value: AttributeValue,
};

pub const DeltaOp = struct {
    /// Owned inserted UTF-8 bytes.
    insert: []u8,
    /// Owned attribute keys and values active for `insert`.
    attributes: []Attribute = &.{},

    /// Frees the inserted text and all copied attributes in this op.
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
    /// Owned list of attributed insert operations.
    ops: std.ArrayList(DeltaOp) = .empty,

    /// Frees every operation owned by this delta.
    pub fn deinit(self: *Delta, allocator: std.mem.Allocator) void {
        for (self.ops.items) |op| {
            op.deinit(allocator);
        }
        self.ops.deinit(allocator);
        self.* = undefined;
    }
};
