const std = @import("std");
const attrs = @import("attrs.zig");
const item_mod = @import("item.zig");
const text_mod = @import("text.zig");

pub const OwnedAttribute = struct {
    attribute: attrs.Attribute,
    owns_value: bool = false,

    pub fn deinit(self: OwnedAttribute, allocator: std.mem.Allocator) void {
        if (self.owns_value) {
            switch (self.attribute.value) {
                .null => {},
                .string => |value| allocator.free(value),
            }
        }
    }
};

pub fn cleanup(text: *text_mod.TextImpl) !void {
    var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
    defer active_attrs.deinit(text.allocator);

    var cursor = text.start;
    while (cursor) |handle| {
        if (!text.items.items[handle].flags.deleted) {
            switch (text.items.items[handle].content) {
                .string => {},
                .format => |format_slice| {
                    if (formatIsRedundant(text, active_attrs.items, format_slice) or
                        !hasVisibleContentBeforeNextSameKey(text, handle, format_slice))
                    {
                        text.items.items[handle].flags.deleted = true;
                        text.invalidateSearchMarkers();
                    } else {
                        try updateActiveAttrs(text, text.allocator, &active_attrs, format_slice);
                    }
                },
            }
        }
        cursor = text.items.items[handle].right;
    }
}

pub fn restoreAttributesAt(
    text: *const text_mod.TextImpl,
    allocator: std.mem.Allocator,
    index: u64,
    attributes: []const attrs.Attribute,
) ![]OwnedAttribute {
    if (attributes.len == 0) return &.{};

    var result = try allocator.alloc(OwnedAttribute, attributes.len);
    errdefer {
        for (result) |owned| owned.deinit(allocator);
        allocator.free(result);
    }

    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |owned| owned.deinit(allocator);
    }

    for (attributes, 0..) |attribute, attribute_index| {
        result[attribute_index] = .{
            .attribute = .{
                .key = attribute.key,
                .value = .null,
            },
        };

        if (try activeValueAt(text, index, attribute.key)) |value| {
            result[attribute_index].attribute.value = .{ .string = try allocator.dupe(u8, value) };
            result[attribute_index].owns_value = true;
        }
        initialized += 1;
    }

    return result;
}

pub fn freeOwnedAttributes(allocator: std.mem.Allocator, attributes: []OwnedAttribute) void {
    if (attributes.len == 0) return;
    for (attributes) |attribute| {
        attribute.deinit(allocator);
    }
    allocator.free(attributes);
}

pub fn updateActiveAttrs(
    text: *const text_mod.TextImpl,
    allocator: std.mem.Allocator,
    active_attrs: *std.ArrayList(attrs.Attribute),
    format_slice: item_mod.AttributeSlice,
) !void {
    const key = text.attributeKeyBytes(format_slice);
    for (active_attrs.items, 0..) |attribute, index| {
        if (std.mem.eql(u8, attribute.key, key)) {
            if (format_slice.value_is_null) {
                _ = active_attrs.orderedRemove(index);
            } else {
                active_attrs.items[index].value = .{ .string = text.attributeValueBytes(format_slice) };
            }
            return;
        }
    }
    if (!format_slice.value_is_null) {
        try active_attrs.append(allocator, .{
            .key = key,
            .value = .{ .string = text.attributeValueBytes(format_slice) },
        });
    }
}

fn activeValueAt(text: *const text_mod.TextImpl, target_index: u64, key: []const u8) !?[]const u8 {
    var active_value: ?[]const u8 = null;
    var cursor = text.start;
    var visible_index: u64 = 0;
    while (cursor) |handle| {
        const current = text.items.items[handle];
        if (!current.flags.deleted) {
            switch (current.content) {
                .format => |format_slice| {
                    if (std.mem.eql(u8, text.attributeKeyBytes(format_slice), key)) {
                        active_value = if (format_slice.value_is_null) null else text.attributeValueBytes(format_slice);
                    }
                },
                .string => if (current.flags.countable) {
                    const current_len = current.getClockLen();
                    if (visible_index + current_len > target_index) break;
                    visible_index += current_len;
                },
            }
        }
        cursor = current.right;
    }
    return active_value;
}

pub fn formatIsRedundant(
    text: *const text_mod.TextImpl,
    active_attrs: []const attrs.Attribute,
    format_slice: item_mod.AttributeSlice,
) bool {
    const key = text.attributeKeyBytes(format_slice);
    for (active_attrs) |attribute| {
        if (std.mem.eql(u8, attribute.key, key)) {
            if (format_slice.value_is_null) return false;
            return switch (attribute.value) {
                .null => false,
                .string => |value| std.mem.eql(u8, value, text.attributeValueBytes(format_slice)),
            };
        }
    }
    return format_slice.value_is_null;
}

fn hasVisibleContentBeforeNextSameKey(
    text: *const text_mod.TextImpl,
    handle: item_mod.ItemHandle,
    format_slice: item_mod.AttributeSlice,
) bool {
    const key = text.attributeKeyBytes(format_slice);
    var cursor = text.items.items[handle].right;
    while (cursor) |current_handle| {
        const current = text.items.items[current_handle];
        if (!current.flags.deleted) {
            switch (current.content) {
                .string => if (current.flags.countable) return true,
                .format => |next_format| {
                    if (std.mem.eql(u8, text.attributeKeyBytes(next_format), key)) return false;
                },
            }
        }
        cursor = current.right;
    }
    return false;
}

pub fn copyAttributes(allocator: std.mem.Allocator, source: []const attrs.Attribute) ![]attrs.Attribute {
    if (source.len == 0) return &.{};
    const copied = try allocator.alloc(attrs.Attribute, source.len);
    errdefer allocator.free(copied);

    var initialized: usize = 0;
    errdefer {
        for (copied[0..initialized]) |attribute| {
            allocator.free(attribute.key);
            switch (attribute.value) {
                .null => {},
                .string => |value| allocator.free(value),
            }
        }
    }

    for (source, 0..) |attribute, index| {
        copied[index].key = try allocator.dupe(u8, attribute.key);
        copied[index].value = switch (attribute.value) {
            .null => .null,
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
        };
        initialized += 1;
    }
    return copied;
}

pub fn freeAttributes(allocator: std.mem.Allocator, attributes: []attrs.Attribute) void {
    if (attributes.len == 0) return;
    for (attributes) |attribute| {
        allocator.free(attribute.key);
        switch (attribute.value) {
            .null => {},
            .string => |value| allocator.free(value),
        }
    }
    allocator.free(attributes);
}
