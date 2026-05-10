const std = @import("std");
const attrs = @import("attrs.zig");
const item_mod = @import("item.zig");
const text_mod = @import("text/impl.zig");
const id = @import("id.zig");

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

const PendingFormat = struct {
    key: []const u8,
    handle: item_mod.ItemHandle,
};

/// Walks through the linked list and marks redundant format items as deleted.
/// Format markers only matter once visible text appears after them. While no
/// visible text has been seen, keep the last pending marker for each key and
/// delete older same-key markers that get superseded.
pub fn cleanup(text: *text_mod.TextImpl) !void {
    var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
    defer active_attrs.deinit(text.allocator);

    var pending_formats: std.ArrayList(PendingFormat) = .empty;
    defer pending_formats.deinit(text.allocator);

    var cursor = text.start;
    while (cursor) |handle| {
        defer cursor = text.items.items[handle].right;

        const is_deleted = text.items.items[handle].flags.deleted;
        if (is_deleted) continue;

        switch (text.items.items[handle].content) {
            .string => if (text.items.items[handle].flags.countable) {
                try commitPendingFormats(text, &active_attrs, &pending_formats);
            },
            .format => |format_slice| {
                const key = text.attributeKeyBytes(format_slice);
                // same-key pending format already exists, and we didn't reach any visible text
                if (findPendingFormatIndex(pending_formats.items, key)) |pending_index| {
                    try deleteFormatMarker(text, pending_formats.items[pending_index].handle);
                    _ = pending_formats.orderedRemove(pending_index);
                }

                if (checkIfFormatIsRedundant(text, active_attrs.items, format_slice)) {
                    try deleteFormatMarker(text, handle);
                    continue;
                }
                try pending_formats.append(text.allocator, .{
                    .key = key,
                    .handle = handle,
                });
            },
        }
    }

    for (pending_formats.items) |pending| {
        try deleteFormatMarker(text, pending.handle);
    }
}

fn commitPendingFormats(
    text: *text_mod.TextImpl,
    active_attrs: *std.ArrayList(attrs.Attribute),
    pending_formats: *std.ArrayList(PendingFormat),
) !void {
    for (pending_formats.items) |pending| {
        const format_slice = text.items.items[pending.handle].content.format;
        try updateActiveAttrs(text, text.allocator, active_attrs, format_slice);
    }
    pending_formats.clearRetainingCapacity();
}

fn findPendingFormatIndex(pending_formats: []const PendingFormat, key: []const u8) ?usize {
    for (pending_formats, 0..) |pending, index| {
        if (std.mem.eql(u8, pending.key, key)) return index;
    }
    return null;
}

fn deleteFormatMarker(text: *text_mod.TextImpl, handle: item_mod.ItemHandle) !void {
    _ = try text.markDeleted(handle);
}

///           01234
/// [font:1] [Hello] [bold:null] [font:null]
/// inserting font:2 at index 2 would return
/// [font:1] as restore attribute
pub fn findRestoreAttr(
    text: *const text_mod.TextImpl,
    allocator: std.mem.Allocator,
    index: id.TextIndex,
    attributes: []const attrs.Attribute,
) ![]OwnedAttribute {
    if (attributes.len == 0) return &.{};

    var result = try allocator.alloc(OwnedAttribute, attributes.len);
    errdefer allocator.free(result);

    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |owned| owned.deinit(allocator);
    }

    for (attributes, 0..) |attribute, attribute_index| {
        // by default restore to null
        result[attribute_index] = .{
            .attribute = .{
                .key = attribute.key,
                .value = .null,
            },
        };

        const before_our_attr_value = getActiveAttrForIndex(text, index, attribute.key);
        if (before_our_attr_value) |value| {
            result[attribute_index].attribute.value = .{ .string = try allocator.dupe(u8, value) };
            result[attribute_index].owns_value = true;
        }
        initialized += 1;
    }

    return result;
}

test "findRestoreAttr returns correct restore attributes" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insertWithAttrs(0, "Hello", &.{.{ .key = "font", .value = .{ .string = "1" } }});

    const restore_attrs = try findRestoreAttr(&text, allocator, 2, &.{
        .{ .key = "font", .value = .{ .string = "2" } },
    });
    defer freeOwnedAttributes(allocator, restore_attrs);

    try std.testing.expectEqual(1, restore_attrs.len);
    try std.testing.expectEqualStrings("1", restore_attrs[0].attribute.value.string);
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
        const is_found_key = std.mem.eql(u8, attribute.key, key);
        if (!is_found_key) {
            continue;
        }
        if (format_slice.value_is_null) {
            _ = active_attrs.orderedRemove(index);
        } else {
            active_attrs.items[index].value = .{ .string = text.attributeValueBytes(format_slice) };
        }
        return;
    }
    const should_append_new_attr = !format_slice.value_is_null;
    if (should_append_new_attr) {
        try active_attrs.append(allocator, .{
            .key = key,
            .value = .{ .string = text.attributeValueBytes(format_slice) },
        });
    }
}

///              12345               678...
/// [bold:true] [Hello] [bold:null] [World]
/// getActiveAttrForIndex(0) -> "true"
fn getActiveAttrForIndex(text: *const text_mod.TextImpl, target_index: id.TextIndex, key: []const u8) ?[]const u8 {
    var active_value: ?[]const u8 = null;
    var cursor = text.start;
    var visible_index: u64 = 0;
    while (cursor) |handle| {
        const current = text.items.items[handle];
        defer cursor = current.right;
        if (current.flags.deleted) continue;

        switch (current.content) {
            .format => |format_slice| {
                const current_key = text.attributeKeyBytes(format_slice);
                const is_found_key = std.mem.eql(u8, current_key, key);
                if (is_found_key) {
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
    return active_value;
}

test "getActiveAttrForIndex returns the active attribute value for the given index" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    try text.insertWithAttrs(0, "H", &.{.{ .key = "bold", .value = .{ .string = "true" } }});
    try text.insertWithAttrs(1, "i", &.{.{ .key = "bold", .value = .{ .string = "true" } }});
    try text.insertWithAttrs(2, "!", &.{.{ .key = "bold", .value = .null }});

    const attr0 = getActiveAttrForIndex(&text, 0, "bold") orelse unreachable;
    const attr1 = getActiveAttrForIndex(&text, 1, "bold") orelse unreachable;
    const attr2 = getActiveAttrForIndex(&text, 2, "bold");

    try std.testing.expectEqualStrings("true", attr0);
    try std.testing.expectEqualStrings("true", attr1);
    try std.testing.expectEqual(attr2, null);
}

/// If the format_slice is applied right now,
/// would it change the current active formatting state?
/// If no, then redundant
fn checkIfFormatIsRedundant(
    text: *const text_mod.TextImpl,
    /// Must never contain null values
    active_attrs: []const attrs.Attribute,
    format_slice: item_mod.AttributeSlice,
) bool {
    const key = text.attributeKeyBytes(format_slice);
    for (active_attrs) |attribute| {
        const is_found_key = std.mem.eql(u8, attribute.key, key);
        if (!is_found_key) continue;

        const is_closing_existing_attr = format_slice.value_is_null;
        if (is_closing_existing_attr) return false;

        return switch (attribute.value) {
            .null => false,
            .string => |value| {
                const format_value = text.attributeValueBytes(format_slice);
                const is_value_equal = std.mem.eql(u8, value, format_value);
                return is_value_equal;
            },
        };
    }
    return format_slice.value_is_null;
}

test "checkIfFormatIsRedundant returns true for redundant format" {
    const allocator = std.testing.allocator;
    var text = text_mod.TextImpl.init(allocator, 1);
    defer text.deinit();

    const format_slice = try text.appendAttribute(.{
        .key = "bold",
        .value = .{ .string = "true" },
    });

    var active_attrs: std.ArrayList(attrs.Attribute) = .empty;
    defer active_attrs.deinit(allocator);
    try active_attrs.append(allocator, .{
        .key = "bold",
        .value = .{ .string = "true" },
    });

    const is_redundant = checkIfFormatIsRedundant(&text, active_attrs.items, format_slice);
    try std.testing.expect(is_redundant);
}

pub fn copyAttributes(allocator: std.mem.Allocator, source: []const attrs.Attribute) ![]attrs.Attribute {
    if (source.len == 0) {
        return &.{};
    }
    const copied = try allocator.alloc(attrs.Attribute, source.len);
    errdefer allocator.free(copied);

    var initialized: usize = 0;
    errdefer {
        for (copied[0..initialized]) |attribute| {
            freeAttribute(allocator, attribute);
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
        freeAttribute(allocator, attribute);
    }
    allocator.free(attributes);
}

fn freeAttribute(allocator: std.mem.Allocator, attribute: attrs.Attribute) void {
    allocator.free(attribute.key);
    switch (attribute.value) {
        .null => {},
        .string => |value| allocator.free(value),
    }
}
