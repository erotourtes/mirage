const std = @import("std");
const mirage = @import("mirage_lib");

test "local insert at start and end renders visible text" {
    var doc = mirage.Doc.init(std.testing.allocator, 1);
    defer doc.deinit();

    try doc.text().insert(0, "hi");
    try doc.text().insert(2, "!");

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("hi!", rendered);
    try std.testing.expectEqual(@as(mirage.Clock, 3), doc.text().len());
    try mirage.debug.checkIntegrity(doc.text());
}

test "insert into middle splits a string item" {
    var doc = mirage.Doc.init(std.testing.allocator, 7);
    defer doc.deinit();

    try doc.text().insert(0, "hi");
    try doc.text().insert(1, "e");

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("hei", rendered);
    try std.testing.expectEqual(@as(usize, 3), mirage.debug.itemCount(doc.text()));
    try std.testing.expectEqual(@as(mirage.Clock, 1), mirage.debug.itemLen(doc.text(), 0));
    try std.testing.expectEqual(@as(mirage.Clock, 1), mirage.debug.itemLen(doc.text(), 1));
    try std.testing.expectEqual(@as(mirage.Clock, 1), mirage.debug.itemLen(doc.text(), 2));

    const h = try mirage.debug.findHandleById(doc.text(), .{ .client = 7, .clock = 1 });
    try std.testing.expectEqual(@as(mirage.ItemHandle, 1), h);
    try std.testing.expectEqual(@as(mirage.Clock, 3), mirage.debug.clientState(doc.text(), 7));
    try mirage.debug.checkIntegrity(doc.text());
}

test "compact joins safe adjacent string intervals" {
    var doc = mirage.Doc.init(std.testing.allocator, 8);
    defer doc.deinit();

    try doc.text().insert(0, "hi");
    try doc.text().insert(2, "!");

    try std.testing.expectEqual(@as(mirage.Clock, 1), mirage.debug.itemLen(doc.text(), 1));

    try doc.text().compact();

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("hi!", rendered);
    try std.testing.expectEqual(@as(mirage.Clock, 3), mirage.debug.itemLen(doc.text(), 0));
    try std.testing.expectEqual(@as(mirage.ItemHandle, 0), try mirage.debug.findHandleById(doc.text(), .{ .client = 8, .clock = 2 }));
    try std.testing.expectEqual(@as(mirage.Clock, 3), mirage.debug.clientState(doc.text(), 8));
    try mirage.debug.checkIntegrity(doc.text());
}

test "delete inside one item keeps deleted item addressable" {
    var doc = mirage.Doc.init(std.testing.allocator, 9);
    defer doc.deinit();

    try doc.text().insert(0, "hello");
    try doc.text().delete(1, 3);

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("ho", rendered);
    try std.testing.expectEqual(@as(mirage.Clock, 2), doc.text().len());
    try std.testing.expectEqual(@as(usize, 3), mirage.debug.itemCount(doc.text()));
    try std.testing.expect(mirage.debug.itemDeleted(doc.text(), 1));
    try mirage.debug.checkIntegrity(doc.text());
}

test "delete range across multiple items" {
    var doc = mirage.Doc.init(std.testing.allocator, 11);
    defer doc.deinit();

    try doc.text().insert(0, "ab");
    try doc.text().insert(2, "cd");
    try doc.text().insert(4, "ef");
    try doc.text().delete(1, 4);

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("af", rendered);
    try std.testing.expectEqual(@as(mirage.Clock, 2), doc.text().len());
    try mirage.debug.checkIntegrity(doc.text());
}

test "unicode scalar indexes split on utf8 boundaries" {
    var doc = mirage.Doc.init(std.testing.allocator, 13);
    defer doc.deinit();

    try doc.text().insert(0, "aé水");
    try doc.text().insert(2, "!");
    try doc.text().delete(1, 1);

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);

    try std.testing.expectEqualStrings("a!水", rendered);
    try mirage.debug.checkIntegrity(doc.text());
}

test "state update syncs inserts between two docs" {
    var a = mirage.Doc.init(std.testing.allocator, 1);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 2);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);
    try b.text().applyUpdate(update);

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("hello", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "concurrent inserts at same position converge" {
    var a = mirage.Doc.init(std.testing.allocator, 1);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 2);
    defer b.deinit();

    try a.text().insert(0, "X");
    try b.text().insert(0, "Y");

    const update_a = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_a);
    const update_b = try b.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_b);

    try a.text().applyUpdate(update_b);
    try b.text().applyUpdate(update_a);

    const rendered_a = try a.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_a);
    const rendered_b = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_b);

    try std.testing.expectEqualStrings("XY", rendered_a);
    try std.testing.expectEqualStrings(rendered_a, rendered_b);
    try mirage.debug.checkIntegrity(a.text());
    try mirage.debug.checkIntegrity(b.text());
}

test "remote delete applies by id range" {
    var a = mirage.Doc.init(std.testing.allocator, 1);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 2);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const insert_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(insert_update);
    try b.text().applyUpdate(insert_update);

    try a.text().delete(1, 3);
    const delete_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(delete_update);
    try b.text().applyUpdate(delete_update);

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("ho", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "out of order diff update is pending then retried" {
    var a = mirage.Doc.init(std.testing.allocator, 1);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 2);
    defer b.deinit();

    try a.text().insert(0, "a");
    const after_first_state = try a.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(after_first_state);
    const first_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(first_update);

    try a.text().insert(1, "b");
    const second_update = try a.text().encodeStateAsUpdate(std.testing.allocator, after_first_state);
    defer std.testing.allocator.free(second_update);

    try b.text().applyUpdate(second_update);
    try std.testing.expectEqual(@as(usize, 1), mirage.debug.pendingUpdateCount(b.text()));

    try b.text().applyUpdate(first_update);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(b.text()));

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("ab", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "insert with attributes renders attributed delta" {
    var doc = mirage.Doc.init(std.testing.allocator, 21);
    defer doc.deinit();

    try doc.text().insertWithAttrs(0, "hi", &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), delta.ops.items.len);
    try std.testing.expectEqualStrings("hi", delta.ops.items[0].insert);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items[0].attributes.len);
    try std.testing.expectEqualStrings("bold", delta.ops.items[0].attributes[0].key);
    try std.testing.expectEqualStrings("true", delta.ops.items[0].attributes[0].value.string);
    try mirage.debug.checkIntegrity(doc.text());
}

test "format range inserts start and end markers" {
    var doc = mirage.Doc.init(std.testing.allocator, 22);
    defer doc.deinit();

    try doc.text().insert(0, "hello");
    try doc.text().format(1, 3, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), delta.ops.items.len);
    try std.testing.expectEqualStrings("h", delta.ops.items[0].insert);
    try std.testing.expectEqual(@as(usize, 0), delta.ops.items[0].attributes.len);
    try std.testing.expectEqualStrings("ell", delta.ops.items[1].insert);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items[1].attributes.len);
    try std.testing.expectEqualStrings("color", delta.ops.items[1].attributes[0].key);
    try std.testing.expectEqualStrings("red", delta.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings("o", delta.ops.items[2].insert);
    try std.testing.expectEqual(@as(usize, 0), delta.ops.items[2].attributes.len);
    try mirage.debug.checkIntegrity(doc.text());
}

test "rich text format items sync through updates" {
    var a = mirage.Doc.init(std.testing.allocator, 31);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 32);
    defer b.deinit();

    try a.text().insertWithAttrs(0, "hi", &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);
    try b.text().applyUpdate(update);

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("hi", rendered);

    var delta = try b.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items.len);
    try std.testing.expectEqualStrings("hi", delta.ops.items[0].insert);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items[0].attributes.len);
    try std.testing.expectEqualStrings("bold", delta.ops.items[0].attributes[0].key);
    try std.testing.expectEqualStrings("true", delta.ops.items[0].attributes[0].value.string);
    try mirage.debug.checkIntegrity(b.text());
}

test "compact deletes redundant format markers" {
    var doc = mirage.Doc.init(std.testing.allocator, 41);
    defer doc.deinit();

    try doc.text().insertWithAttrs(0, "hi", &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    try doc.text().format(0, 2, &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    try doc.text().compact();

    try std.testing.expectEqual(@as(usize, 1), mirage.debug.liveFormatMarkerCount(doc.text(), "bold", "true"));

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items.len);
    try std.testing.expectEqualStrings("hi", delta.ops.items[0].insert);
    try std.testing.expectEqual(@as(usize, 1), delta.ops.items[0].attributes.len);
    try mirage.debug.checkIntegrity(doc.text());
}

test "overlapping same-key formats restore previous value" {
    var doc = mirage.Doc.init(std.testing.allocator, 42);
    defer doc.deinit();

    try doc.text().insert(0, "abcd");
    try doc.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    try doc.text().format(1, 2, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), delta.ops.items.len);
    try std.testing.expectEqualStrings("a", delta.ops.items[0].insert);
    try std.testing.expectEqualStrings("red", delta.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqualStrings("bc", delta.ops.items[1].insert);
    try std.testing.expectEqualStrings("blue", delta.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings("d", delta.ops.items[2].insert);
    try std.testing.expectEqualStrings("red", delta.ops.items[2].attributes[0].value.string);
    try mirage.debug.checkIntegrity(doc.text());
}

test "delete across formatted region preserves surrounding format" {
    var doc = mirage.Doc.init(std.testing.allocator, 43);
    defer doc.deinit();

    try doc.text().insert(0, "abcdef");
    try doc.text().format(1, 4, &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    try doc.text().delete(2, 2);

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("abef", rendered);

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("a", delta.ops.items[0].insert);
    try std.testing.expectEqual(@as(usize, 0), delta.ops.items[0].attributes.len);
    try std.testing.expectEqualStrings("be", delta.ops.items[1].insert);
    try std.testing.expectEqualStrings("true", delta.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings("f", delta.ops.items[2].insert);
    try std.testing.expectEqual(@as(usize, 0), delta.ops.items[2].attributes.len);
    try mirage.debug.checkIntegrity(doc.text());
}

test "compact removes markers around fully deleted content" {
    var doc = mirage.Doc.init(std.testing.allocator, 46);
    defer doc.deinit();

    try doc.text().insert(0, "abc");
    try doc.text().format(0, 3, &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    try doc.text().delete(0, 3);
    try doc.text().compact();

    const rendered = try doc.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("", rendered);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.liveFormatMarkerCount(doc.text(), "bold", "true"));
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.liveFormatMarkerCount(doc.text(), "bold", null));
    try mirage.debug.checkIntegrity(doc.text());
}

test "compact removes empty same-key toggles" {
    var doc = mirage.Doc.init(std.testing.allocator, 47);
    defer doc.deinit();

    try doc.text().insert(0, "abcd");
    try doc.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    try doc.text().format(1, 2, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });
    try doc.text().delete(1, 2);
    try doc.text().compact();

    var delta = try doc.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), delta.ops.items.len);
    try std.testing.expectEqualStrings("ad", delta.ops.items[0].insert);
    try std.testing.expectEqualStrings("red", delta.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqual(@as(usize, 1), mirage.debug.liveFormatMarkerCount(doc.text(), "color", "red"));
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.liveFormatMarkerCount(doc.text(), "color", "blue"));
    try mirage.debug.checkIntegrity(doc.text());
}

test "remote overlapping format restores previous value" {
    var a = mirage.Doc.init(std.testing.allocator, 44);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 45);
    defer b.deinit();

    try a.text().insert(0, "abcd");
    try a.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    const first_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(first_update);
    try b.text().applyUpdate(first_update);

    try b.text().format(1, 2, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });
    const second_update = try b.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(second_update);
    try a.text().applyUpdate(second_update);

    var delta = try a.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), delta.ops.items.len);
    try std.testing.expectEqualStrings("red", delta.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqualStrings("blue", delta.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings("red", delta.ops.items[2].attributes[0].value.string);
    try mirage.debug.checkIntegrity(a.text());
    try mirage.debug.checkIntegrity(b.text());
}

test "out of order overlapping format waits for base format markers" {
    var a = mirage.Doc.init(std.testing.allocator, 48);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 49);
    defer b.deinit();

    try a.text().insert(0, "abcd");
    const after_insert_state = try a.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(after_insert_state);
    const insert_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(insert_update);

    try a.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    const after_red_state = try a.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(after_red_state);
    const red_update = try a.text().encodeStateAsUpdate(std.testing.allocator, after_insert_state);
    defer std.testing.allocator.free(red_update);

    try a.text().format(1, 2, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });
    const blue_update = try a.text().encodeStateAsUpdate(std.testing.allocator, after_red_state);
    defer std.testing.allocator.free(blue_update);

    try b.text().applyUpdate(insert_update);
    try b.text().applyUpdate(blue_update);
    try std.testing.expectEqual(@as(usize, 1), mirage.debug.pendingUpdateCount(b.text()));
    try b.text().applyUpdate(red_update);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(b.text()));

    var delta = try b.text().toDelta(std.testing.allocator);
    defer delta.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), delta.ops.items.len);
    try std.testing.expectEqualStrings("red", delta.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqualStrings("blue", delta.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings("red", delta.ops.items[2].attributes[0].value.string);
    try mirage.debug.checkIntegrity(b.text());
}

test "concurrent same-key remote formats converge in opposite exchange orders" {
    var a1 = mirage.Doc.init(std.testing.allocator, 50);
    defer a1.deinit();
    var b1 = mirage.Doc.init(std.testing.allocator, 51);
    defer b1.deinit();
    var a2 = mirage.Doc.init(std.testing.allocator, 50);
    defer a2.deinit();
    var b2 = mirage.Doc.init(std.testing.allocator, 51);
    defer b2.deinit();

    try a1.text().insert(0, "abcd");
    const base_update = try a1.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(base_update);
    try b1.text().applyUpdate(base_update);
    try a2.text().applyUpdate(base_update);
    try b2.text().applyUpdate(base_update);

    try a1.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    try b1.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });
    try a2.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    try b2.text().format(0, 4, &.{
        .{ .key = "color", .value = .{ .string = "blue" } },
    });

    const update_a = try a1.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_a);
    const update_b = try b1.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_b);

    try a1.text().applyUpdate(update_b);
    try b1.text().applyUpdate(update_a);
    try b2.text().applyUpdate(update_a);
    try a2.text().applyUpdate(update_b);

    var delta_a1 = try a1.text().toDelta(std.testing.allocator);
    defer delta_a1.deinit(std.testing.allocator);
    var delta_b1 = try b1.text().toDelta(std.testing.allocator);
    defer delta_b1.deinit(std.testing.allocator);
    var delta_a2 = try a2.text().toDelta(std.testing.allocator);
    defer delta_a2.deinit(std.testing.allocator);
    var delta_b2 = try b2.text().toDelta(std.testing.allocator);
    defer delta_b2.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(delta_a1.ops.items[0].attributes[0].value.string, delta_b1.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqualStrings(delta_a1.ops.items[0].attributes[0].value.string, delta_a2.ops.items[0].attributes[0].value.string);
    try std.testing.expectEqualStrings(delta_a1.ops.items[0].attributes[0].value.string, delta_b2.ops.items[0].attributes[0].value.string);
    try mirage.debug.checkIntegrity(a1.text());
    try mirage.debug.checkIntegrity(b1.text());
    try mirage.debug.checkIntegrity(a2.text());
    try mirage.debug.checkIntegrity(b2.text());
}

test "concurrent delete and remote format crossing deleted range converge" {
    var a = mirage.Doc.init(std.testing.allocator, 52);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 53);
    defer b.deinit();

    try a.text().insert(0, "abcdef");
    const base_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(base_update);
    try b.text().applyUpdate(base_update);

    try a.text().delete(2, 2);
    try b.text().format(1, 4, &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });

    const delete_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(delete_update);
    const format_update = try b.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(format_update);

    try a.text().applyUpdate(format_update);
    try b.text().applyUpdate(delete_update);

    const rendered_a = try a.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_a);
    const rendered_b = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_b);
    try std.testing.expectEqualStrings("abef", rendered_a);
    try std.testing.expectEqualStrings(rendered_a, rendered_b);

    var delta_a = try a.text().toDelta(std.testing.allocator);
    defer delta_a.deinit(std.testing.allocator);
    var delta_b = try b.text().toDelta(std.testing.allocator);
    defer delta_b.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("be", delta_a.ops.items[1].insert);
    try std.testing.expectEqualStrings("true", delta_a.ops.items[1].attributes[0].value.string);
    try std.testing.expectEqualStrings(delta_a.ops.items[1].insert, delta_b.ops.items[1].insert);
    try mirage.debug.checkIntegrity(a.text());
    try mirage.debug.checkIntegrity(b.text());
}

test "re-applying the same update is idempotent" {
    var a = mirage.Doc.init(std.testing.allocator, 51);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 52);
    defer b.deinit();

    try a.text().insertWithAttrs(0, "hi", &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    try a.text().delete(1, 1);

    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);
    try b.text().applyUpdate(update);
    try b.text().applyUpdate(update);

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("h", rendered);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(b.text()));
    try mirage.debug.checkIntegrity(b.text());
}

test "delete-only update waits for missing inserted structs" {
    var a = mirage.Doc.init(std.testing.allocator, 61);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 62);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const after_insert_state = try a.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(after_insert_state);
    const insert_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(insert_update);

    try a.text().delete(1, 3);
    const delete_only_update = try a.text().encodeStateAsUpdate(std.testing.allocator, after_insert_state);
    defer std.testing.allocator.free(delete_only_update);

    try b.text().applyUpdate(delete_only_update);
    try std.testing.expectEqual(@as(usize, 1), mirage.debug.pendingUpdateCount(b.text()));
    try b.text().applyUpdate(insert_update);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(b.text()));

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("ho", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "state-vector diff can start inside a string chunk" {
    var a = mirage.Doc.init(std.testing.allocator, 71);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 71);
    defer b.deinit();

    try a.text().insert(0, "abcd");

    var state_encoder = mirage.encoding.Encoder.init(std.testing.allocator);
    defer state_encoder.deinit();
    try state_encoder.writeVarU64(1);
    try state_encoder.writeVarU64(71);
    try state_encoder.writeVarU64(2);
    const partial_state = try state_encoder.toOwnedSlice();
    defer std.testing.allocator.free(partial_state);

    try b.text().insert(0, "ab");
    const suffix_update = try a.text().encodeStateAsUpdate(std.testing.allocator, partial_state);
    defer std.testing.allocator.free(suffix_update);
    try b.text().applyUpdate(suffix_update);

    const rendered = try b.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("abcd", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "updates are commutative across exchange order" {
    var a1 = mirage.Doc.init(std.testing.allocator, 81);
    defer a1.deinit();
    var b1 = mirage.Doc.init(std.testing.allocator, 82);
    defer b1.deinit();
    var a2 = mirage.Doc.init(std.testing.allocator, 81);
    defer a2.deinit();
    var b2 = mirage.Doc.init(std.testing.allocator, 82);
    defer b2.deinit();

    try a1.text().insert(0, "A");
    try a1.text().insert(1, "1");
    try b1.text().insert(0, "B");
    try b1.text().insertWithAttrs(1, "2", &.{
        .{ .key = "mark", .value = .{ .string = "yes" } },
    });

    try a2.text().insert(0, "A");
    try a2.text().insert(1, "1");
    try b2.text().insert(0, "B");
    try b2.text().insertWithAttrs(1, "2", &.{
        .{ .key = "mark", .value = .{ .string = "yes" } },
    });

    const update_a = try a1.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_a);
    const update_b = try b1.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update_b);

    try a1.text().applyUpdate(update_b);
    try b1.text().applyUpdate(update_a);
    try b2.text().applyUpdate(update_a);
    try a2.text().applyUpdate(update_b);

    const rendered_a1 = try a1.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_a1);
    const rendered_b1 = try b1.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_b1);
    const rendered_a2 = try a2.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_a2);
    const rendered_b2 = try b2.text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(rendered_b2);

    try std.testing.expectEqualStrings(rendered_a1, rendered_b1);
    try std.testing.expectEqualStrings(rendered_a1, rendered_a2);
    try std.testing.expectEqualStrings(rendered_a1, rendered_b2);
    try mirage.debug.checkIntegrity(a1.text());
    try mirage.debug.checkIntegrity(b1.text());
    try mirage.debug.checkIntegrity(a2.text());
    try mirage.debug.checkIntegrity(b2.text());
}

test "deterministic randomized convergence across several docs" {
    var docs = [_]mirage.Doc{
        mirage.Doc.init(std.testing.allocator, 101),
        mirage.Doc.init(std.testing.allocator, 102),
        mirage.Doc.init(std.testing.allocator, 103),
    };
    defer for (&docs) |*doc| doc.deinit();

    var rng = std.Random.DefaultPrng.init(0xC0FFEE);
    const random = rng.random();
    const alphabet = "abcdefghijklmnopqrstuvwxyz";
    var step: usize = 0;
    while (step < 48) : (step += 1) {
        const doc_index = random.uintLessThan(usize, docs.len);
        const text = docs[doc_index].text();
        if (text.len() == 0 or random.boolean()) {
            const at = random.uintLessThan(u64, text.len() + 1);
            const ch = alphabet[random.uintLessThan(usize, alphabet.len)..][0..1];
            if (random.uintLessThan(u8, 5) == 0) {
                try text.insertWithAttrs(at, ch, &.{
                    .{ .key = "source", .value = .{ .string = "random" } },
                });
            } else {
                try text.insert(at, ch);
            }
        } else {
            const at = random.uintLessThan(u64, text.len());
            try text.delete(at, 1);
        }
    }

    var updates: [docs.len][]u8 = undefined;
    for (&docs, 0..) |*doc, index| {
        updates[index] = try doc.text().encodeStateAsUpdate(std.testing.allocator, null);
    }
    defer for (updates) |update| std.testing.allocator.free(update);

    for (&docs, 0..) |*doc, doc_index| {
        for (updates, 0..) |update, update_index| {
            if (doc_index != update_index) try doc.text().applyUpdate(update);
        }
    }

    const expected = try docs[0].text().toOwnedString(std.testing.allocator);
    defer std.testing.allocator.free(expected);
    for (&docs) |*doc| {
        const rendered = try doc.text().toOwnedString(std.testing.allocator);
        defer std.testing.allocator.free(rendered);
        try std.testing.expectEqualStrings(expected, rendered);
        try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(doc.text()));
        try mirage.debug.checkIntegrity(doc.text());
    }
}
