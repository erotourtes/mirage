const std = @import("std");
const mirage = @import("mirage_lib");

const update_magic = "MYPEACE";
const update_version: u8 = 1;

test "update encoding includes magic and version" {
    var doc = mirage.Doc.init(std.testing.allocator, 701);
    defer doc.deinit();

    try doc.text().insertWithAttrs(0, "hi", &.{
        .{ .key = "bold", .value = .{ .string = "true" } },
    });
    const update = try doc.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);

    try std.testing.expect(update.len > update_magic.len);
    try std.testing.expectEqualStrings(update_magic, update[0..update_magic.len]);
    try std.testing.expectEqual(update_version, update[update_magic.len]);
}

test "update encoding is deterministic for same document state" {
    var doc = mirage.Doc.init(std.testing.allocator, 702);
    defer doc.deinit();

    try doc.text().insert(0, "hello");
    try doc.text().format(1, 3, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });
    try doc.text().delete(2, 1);

    const first = try doc.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(first);
    const second = try doc.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(second);

    try std.testing.expectEqualSlices(u8, first, second);
}

test "unsupported update version is rejected clearly" {
    var a = mirage.Doc.init(std.testing.allocator, 703);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 704);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);

    const mutated = try std.testing.allocator.dupe(u8, update);
    defer std.testing.allocator.free(mutated);
    mutated[update_magic.len] = 255;

    try std.testing.expectError(error.UnsupportedUpdateVersion, b.text().applyUpdate(mutated));
}

test "malformed updates are rejected without corrupting state" {
    var doc = mirage.Doc.init(std.testing.allocator, 705);
    defer doc.deinit();

    try std.testing.expectError(error.InvalidUpdate, doc.text().applyUpdate(""));
    try std.testing.expectError(error.InvalidUpdate, doc.text().applyUpdate("not-an-update"));

    try mirage.debug.checkIntegrity(doc.text());
    const rendered = try doc.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("", rendered);
}

test "truncated and trailing update bytes are rejected" {
    var a = mirage.Doc.init(std.testing.allocator, 706);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 707);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);

    try std.testing.expectError(error.InvalidUpdate, b.text().applyUpdate(update[0 .. update.len - 1]));

    const trailing = try std.testing.allocator.alloc(u8, update.len + 1);
    defer std.testing.allocator.free(trailing);
    @memcpy(trailing[0..update.len], update);
    trailing[update.len] = 0;
    try std.testing.expectError(error.TrailingBytes, b.text().applyUpdate(trailing));

    try mirage.debug.checkIntegrity(b.text());
    const rendered = try b.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("", rendered);
}

test "string and format markers round trip through update" {
    var a = mirage.Doc.init(std.testing.allocator, 708);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 709);
    defer b.deinit();

    try a.text().insert(0, "hé水");
    try a.text().format(1, 2, &.{
        .{ .key = "color", .value = .{ .string = "red" } },
    });

    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);
    try b.text().applyUpdate(update);

    const rendered = try b.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("hé水", rendered);

    var delta = try b.text().toDelta(std.testing.allocator, null);
    defer delta.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), delta.ops.items.len);
    try std.testing.expectEqualStrings("h", delta.ops.items[0].insert);
    try std.testing.expectEqualStrings("é水", delta.ops.items[1].insert);
    try std.testing.expectEqualStrings("color", delta.ops.items[1].attributes[0].key);
    try std.testing.expectEqualStrings("red", delta.ops.items[1].attributes[0].value.string);
}

test "delete set round trips through full update" {
    var a = mirage.Doc.init(std.testing.allocator, 710);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 711);
    defer b.deinit();

    try a.text().insert(0, "hello");
    try a.text().delete(1, 3);

    const update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);
    try b.text().applyUpdate(update);

    const rendered = try b.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("ho", rendered);
    try mirage.debug.checkIntegrity(b.text());
}

test "state vector diff round trips string suffix" {
    var a = mirage.Doc.init(std.testing.allocator, 712);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 713);
    defer b.deinit();

    try a.text().insert(0, "ab");
    const first_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(first_update);
    try b.text().applyUpdate(first_update);

    const b_state = try b.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(b_state);

    try a.text().insert(2, "cd");
    const diff_update = try a.text().encodeStateAsUpdate(std.testing.allocator, b_state);
    defer std.testing.allocator.free(diff_update);
    try b.text().applyUpdate(diff_update);

    const rendered = try b.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("abcd", rendered);
}

test "diff update includes known delete sets by policy" {
    var a = mirage.Doc.init(std.testing.allocator, 714);
    defer a.deinit();
    var b = mirage.Doc.init(std.testing.allocator, 715);
    defer b.deinit();

    try a.text().insert(0, "hello");
    const insert_update = try a.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(insert_update);
    try b.text().applyUpdate(insert_update);

    const b_state = try b.text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(b_state);

    try a.text().delete(1, 3);
    const delete_diff = try a.text().encodeStateAsUpdate(std.testing.allocator, b_state);
    defer std.testing.allocator.free(delete_diff);
    try b.text().applyUpdate(delete_diff);

    const rendered = try b.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings("ho", rendered);
}

test "malformed state vector is rejected when encoding diff" {
    var doc = mirage.Doc.init(std.testing.allocator, 716);
    defer doc.deinit();

    try doc.text().insert(0, "hello");
    try std.testing.expectError(error.InvalidUpdate, doc.text().encodeStateAsUpdate(std.testing.allocator, &.{ 1, 7 }));
    try std.testing.expectError(error.TrailingBytes, doc.text().encodeStateAsUpdate(std.testing.allocator, &.{ 0, 0 }));
}

test "encodes and decodes 42 consecutive single-character items created by client 7" {
    const text = "The quick brown fox jumps overthe lazy dog";
    var doc = mirage.Doc.init(std.testing.allocator, 7);
    defer doc.deinit();

    for (text, 0..) |char, i| {
        try doc.text().insert(i, &[_]u8{char});
    }

    const update = try doc.text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(update);

    var decoded = mirage.Doc.init(std.testing.allocator, 8);
    defer decoded.deinit();
    try decoded.text().applyUpdate(update);

    const rendered = try decoded.text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(rendered);
    try std.testing.expectEqualStrings(text, rendered);
}
