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
        defer cursor = current.right;

        if (current.flags.deleted) {
            continue;
        }

        switch (current.content) {
            .format => |format_slice| try formatting.updateActiveAttrs(text, allocator, &active_attrs, format_slice),
            .string => |slice| if (current.flags.countable) {
                const source_text = text.sliceBytes(slice);
                const should_join_repeated_attrs = brk: {
                    if (delta.ops.items.len <= 0) {
                        break :brk false;
                    }
                    const last_delta_attrs = delta.ops.items[delta.ops.items.len - 1].attributes;
                    const is_equal = checkIfAttributesEqual(last_delta_attrs, active_attrs.items);
                    break :brk is_equal;
                };
                if (should_join_repeated_attrs) {
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

    return delta;
}

fn appendToLastOp(delta: *attrs.Delta, allocator: std.mem.Allocator, bytes: []const u8) !void {
    var last = &delta.ops.items[delta.ops.items.len - 1];
    const old_len = last.insert.len;
    const joined = try allocator.realloc(last.insert, old_len + bytes.len);
    @memcpy(joined[old_len..], bytes);
    last.insert = joined;
}

fn checkIfAttributesEqual(left: []const attrs.Attribute, right: []const attrs.Attribute) bool {
    if (left.len != right.len) return false;
    for (left) |left_attribute| {
        const right_attribute = findAttribute(right, left_attribute.key) orelse return false;
        const is_value_equal = checkIfAttributeValuesEqual(left_attribute.value, right_attribute.value);
        if (!is_value_equal) return false;
    }
    return true;
}

fn findAttribute(attributes: []const attrs.Attribute, key: []const u8) ?attrs.Attribute {
    for (attributes) |attribute| {
        if (std.mem.eql(u8, attribute.key, key)) return attribute;
    }
    return null;
}

fn checkIfAttributeValuesEqual(left: attrs.AttributeValue, right: attrs.AttributeValue) bool {
    return switch (left) {
        .null => right == .null,
        .string => |left_value| switch (right) {
            .null => false,
            .string => |right_value| std.mem.eql(u8, left_value, right_value),
        },
    };
}

const id = @import("id.zig");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "toDelta produces correct delta for simple text with attributes" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello");
    try text.insert(5, " world");
    try text.format(5, 6, &.{attrs.Attribute{
        .key = "bold",
        .value = .{ .string = "true" },
    }});

    var delta = try toDelta(&text, allocator);
    defer delta.deinit(allocator);

    try expectEqual(delta.ops.items.len, 2);
    try expectEqualStrings(delta.ops.items[0].insert, "Hello");
    try expectEqual(delta.ops.items[0].attributes.len, 0);
    try expectEqualStrings(delta.ops.items[1].insert, " world");
    try expectEqual(delta.ops.items[1].attributes.len, 1);
    try expectEqualStrings(delta.ops.items[1].attributes[0].key, "bold");
    try expectEqualStrings(delta.ops.items[1].attributes[0].value.string, "true");
}

test "toDelta should merge repeated attributes" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello");
    try text.insert(5, " world");
    try text.format(0, 3, &.{attrs.Attribute{
        .key = "color",
        .value = .{ .string = "red" },
    }});
    try text.format(3, 8, &.{attrs.Attribute{
        .key = "color",
        .value = .{ .string = "red" },
    }});

    var delta = try toDelta(&text, allocator);
    defer delta.deinit(allocator);

    try expectEqual(delta.ops.items.len, 1);
    try expectEqualStrings(delta.ops.items[0].insert, "Hello world");
    try expectEqual(delta.ops.items[0].attributes.len, 1);
    try expectEqualStrings(delta.ops.items[0].attributes[0].key, "color");
    try expectEqualStrings(delta.ops.items[0].attributes[0].value.string, "red");
}
