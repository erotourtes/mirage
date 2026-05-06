const std = @import("std");
const attrs = @import("attrs.zig");
const formatting = @import("formatting.zig");
const text_mod = @import("text.zig");

pub fn toDelta(text: *const text_mod.TextImpl, allocator: std.mem.Allocator) !attrs.Delta {
    var delta: attrs.Delta = .{};
    errdefer delta.deinit(allocator);

    var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
    defer active_attrs.deinit(allocator);

    var cursor = text.start;
    while (cursor) |handle| {
        const current = text.items.items[handle];
        if (!current.flags.deleted) {
            switch (current.content) {
                .format => |format_slice| try formatting.updateActiveAttrs(text, allocator, &active_attrs, format_slice),
                .string => |slice| if (current.flags.countable) {
                    const source_text = text.sliceBytes(slice);
                    if (delta.ops.items.len > 0 and attributesEqual(delta.ops.items[delta.ops.items.len - 1].attributes, active_attrs.items)) {
                        try appendToLastOp(&delta, allocator, source_text);
                    } else {
                        const inserted_text = try allocator.dupe(u8, source_text);
                        errdefer allocator.free(inserted_text);
                        const copied_attrs = try formatting.copyAttributes(allocator, active_attrs.items);
                        errdefer formatting.freeAttributes(allocator, copied_attrs);
                        try delta.ops.append(allocator, .{
                            .insert = inserted_text,
                            .attributes = copied_attrs,
                        });
                    }
                },
            }
        }
        cursor = current.right;
    }

    return delta;
}

fn appendToLastOp(delta: *attrs.Delta, allocator: std.mem.Allocator, bytes: []const u8) !void {
    var last = &delta.ops.items[delta.ops.items.len - 1];
    const old_len = last.insert.len;
    const joined = try allocator.realloc(last.insert, old_len + bytes.len);
    @memcpy(joined[old_len..], bytes);
    last.insert = joined;
}

fn attributesEqual(left: []const attrs.Attribute, right: []const attrs.Attribute) bool {
    if (left.len != right.len) return false;
    for (left) |left_attribute| {
        const right_attribute = findAttribute(right, left_attribute.key) orelse return false;
        if (!attributeValuesEqual(left_attribute.value, right_attribute.value)) return false;
    }
    return true;
}

fn findAttribute(attributes: []const attrs.Attribute, key: []const u8) ?attrs.Attribute {
    for (attributes) |attribute| {
        if (std.mem.eql(u8, attribute.key, key)) return attribute;
    }
    return null;
}

fn attributeValuesEqual(left: attrs.AttributeValue, right: attrs.AttributeValue) bool {
    return switch (left) {
        .null => right == .null,
        .string => |left_value| switch (right) {
            .null => false,
            .string => |right_value| std.mem.eql(u8, left_value, right_value),
        },
    };
}
