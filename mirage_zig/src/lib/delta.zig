const std = @import("std");
const attrs = @import("attrs.zig");
const formatting = @import("formatting.zig");
const text_mod = @import("text/impl.zig");
const utf = @import("utf.zig");

pub fn toDelta(
    text: *const text_mod.TextImpl,
    allocator: std.mem.Allocator,
    revision: ?id.Revision,
) !attrs.Delta {
    return try toDeltaRange(text, allocator, 0, visibleLenAt(text, revision), .{
        .revision = revision,
        .include_leading_attrs = true,
    });
}

pub const RangeOptions = struct {
    revision: ?id.Revision = null,
    include_leading_attrs: bool = true,
};

pub fn toDeltaRange(
    text: *const text_mod.TextImpl,
    allocator: std.mem.Allocator,
    start: id.TextIndex,
    end: id.TextIndex,
    options: RangeOptions,
) !attrs.Delta {
    if (end < start) return error.IndexOutOfBounds;

    var delta: attrs.Delta = .{};
    errdefer delta.deinit(allocator);

    var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
    defer active_attrs.deinit(allocator);

    const revision = options.revision;
    const include_leading_attrs = options.include_leading_attrs;
    var visible_index: id.TextIndex = 0;

    var cursor = text.start;
    while (cursor) |handle| {
        const current = text.items.items[handle];
        defer cursor = current.right;

        if (!text.isItemAliveAt(handle, revision))
            continue;

        switch (current.content) {
            .format => |format_slice| {
                const should_include_format =
                    include_leading_attrs or (visible_index >= start and visible_index < end);
                if (should_include_format) {
                    try formatting.updateActiveAttrs(text, allocator, &active_attrs, format_slice);
                }
            },
            .string => |slice| if (current.flags.countable) {
                const item_start = visible_index;
                const item_len: id.TextLen = current.getClockLen();
                const item_end = item_start + item_len;
                defer visible_index = item_end;

                if (item_end <= start or item_start >= end) {
                    continue;
                }

                const slice_start = if (start > item_start) start - item_start else 0;
                const slice_end = if (end < item_end) end - item_start else item_len;
                const source_text = try sliceTextRange(text.sliceBytes(slice), slice_start, slice_end);
                try appendDeltaText(&delta, allocator, source_text, active_attrs.items);
            },
        }

        if (visible_index >= end) break;
    }

    if (visible_index < start or visible_index < end) return error.IndexOutOfBounds;
    return delta;
}

fn visibleLenAt(text: *const text_mod.TextImpl, revision: ?id.Revision) id.TextLen {
    var len: id.TextLen = 0;
    var cursor = text.start;
    while (cursor) |handle| {
        const current = text.items.items[handle];
        cursor = current.right;
        if (!text.isItemVisibleAt(handle, revision)) continue;
        len += current.getClockLen();
    }
    return len;
}

fn sliceTextRange(bytes: []const u8, start: id.TextIndex, end: id.TextIndex) ![]const u8 {
    const byte_start = try utf.getByteOffsetForCharIndex(bytes, start);
    const byte_end = try utf.getByteOffsetForCharIndex(bytes, end);
    return bytes[byte_start..byte_end];
}

fn appendDeltaText(
    delta: *attrs.Delta,
    allocator: std.mem.Allocator,
    source_text: []const u8,
    active_attrs: []const attrs.Attribute,
) !void {
    const should_join_repeated_attrs = brk: {
        if (delta.ops.items.len <= 0) {
            break :brk false;
        }
        const last_delta_attrs = delta.ops.items[delta.ops.items.len - 1].attributes;
        const is_equal = checkIfAttributesEqual(last_delta_attrs, active_attrs);
        break :brk is_equal;
    };

    if (should_join_repeated_attrs) {
        try appendToLastOp(delta, allocator, source_text);
    } else {
        const inserted_text = try allocator.dupe(u8, source_text);
        errdefer allocator.free(inserted_text);
        const copied_attrs = try formatting.copyAttributes(allocator, active_attrs);
        errdefer formatting.freeAttributes(allocator, copied_attrs);
        try delta.ops.append(allocator, .{
            .insert = inserted_text,
            .attributes = copied_attrs,
        });
    }
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

    var delta = try toDelta(&text, allocator, null);
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

    var delta = try toDelta(&text, allocator, null);
    defer delta.deinit(allocator);

    try expectEqual(delta.ops.items.len, 1);
    try expectEqualStrings(delta.ops.items[0].insert, "Hello world");
    try expectEqual(delta.ops.items[0].attributes.len, 1);
    try expectEqualStrings(delta.ops.items[0].attributes[0].key, "color");
    try expectEqualStrings(delta.ops.items[0].attributes[0].value.string, "red");
}

test "toDeltaRange full range matches toDelta" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello world");
    try text.format(6, 5, &.{attrs.Attribute{
        .key = "bold",
        .value = .{ .string = "true" },
    }});

    var full = try toDelta(&text, allocator, null);
    defer full.deinit(allocator);
    var ranged = try toDeltaRange(&text, allocator, 0, 11, .{});
    defer ranged.deinit(allocator);

    try expectEqual(full.ops.items.len, ranged.ops.items.len);
    for (full.ops.items, ranged.ops.items) |left, right| {
        try expectEqualStrings(left.insert, right.insert);
        try expectEqual(left.attributes.len, right.attributes.len);
        for (left.attributes, right.attributes) |left_attr, right_attr| {
            try expectEqualStrings(left_attr.key, right_attr.key);
            try expectEqualStrings(left_attr.value.string, right_attr.value.string);
        }
    }
}

test "toDeltaRange renders a plain text range inside one item" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello world");

    var delta = try toDeltaRange(&text, allocator, 3, 8, .{});
    defer delta.deinit(allocator);

    try expectEqual(delta.ops.items.len, 1);
    try expectEqualStrings(delta.ops.items[0].insert, "lo wo");
    try expectEqual(delta.ops.items[0].attributes.len, 0);
}

test "toDeltaRange slices UTF-8 ranges on scalar boundaries" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "a世界b");

    var delta = try toDeltaRange(&text, allocator, 1, 3, .{});
    defer delta.deinit(allocator);

    try expectEqual(delta.ops.items.len, 1);
    try expectEqualStrings(delta.ops.items[0].insert, "世界");
}

test "toDeltaRange can include or ignore leading attrs" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello world");
    try text.format(0, 11, &.{attrs.Attribute{
        .key = "color",
        .value = .{ .string = "red" },
    }});

    var correct = try toDeltaRange(&text, allocator, 6, 11, .{ .include_leading_attrs = true });
    defer correct.deinit(allocator);
    var fast = try toDeltaRange(&text, allocator, 6, 11, .{ .include_leading_attrs = false });
    defer fast.deinit(allocator);

    try expectEqual(correct.ops.items.len, 1);
    try expectEqualStrings(correct.ops.items[0].insert, "world");
    try expectEqual(correct.ops.items[0].attributes.len, 1);
    try expectEqualStrings(correct.ops.items[0].attributes[0].key, "color");
    try expectEqualStrings(correct.ops.items[0].attributes[0].value.string, "red");

    try expectEqual(fast.ops.items.len, 1);
    try expectEqualStrings(fast.ops.items[0].insert, "world");
    try expectEqual(fast.ops.items[0].attributes.len, 0);
}

test "toDeltaRange uses revision visible coordinates" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insert(0, "Hello");
    const revision = text.currentRevision();
    try text.insert(5, " world");

    var historical = try toDeltaRange(&text, allocator, 1, 4, .{ .revision = revision });
    defer historical.deinit(allocator);

    try expectEqual(historical.ops.items.len, 1);
    try expectEqualStrings(historical.ops.items[0].insert, "ell");
}
