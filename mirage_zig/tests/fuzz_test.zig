const std = @import("std");
const mirage = @import("mirage_lib");

const TraceOpTag = enum {
    insert,
    insert_attrs,
    delete,
    format,
    send_full,
    send_diff,
    send_stale_diff,
    duplicate_full,
};

const TraceOp = struct {
    tag: TraceOpTag,
    doc: usize,
    other_doc: usize = 0,
    index: mirage.Clock = 0,
    len: mirage.Clock = 0,
    text: u8 = 0,
    attr_key: AttrKey = .bold,
    attr_value: AttrValue = .true_value,
};

const AttrKey = enum {
    bold,
    color,
    source,

    fn bytes(self: AttrKey) []const u8 {
        return switch (self) {
            .bold => "bold",
            .color => "color",
            .source => "source",
        };
    }
};

const AttrValue = enum {
    null,
    true_value,
    red,
    trace,

    fn value(self: AttrValue) mirage.AttributeValue {
        return switch (self) {
            .null => .null,
            .true_value => .{ .string = "true" },
            .red => .{ .string = "red" },
            .trace => .{ .string = "trace" },
        };
    }
};

const TraceError = error{
    Diverged,
    PendingUpdatesRemain,
} || anyerror;

test "operation trace fuzz converges across sync schedules" {
    try runTrace(.{
        .seed = 0x1234_abcd,
        .doc_count = 2,
        .op_count = 80,
    });
    try runTrace(.{
        .seed = 0xc0ff_ee01,
        .doc_count = 3,
        .op_count = 120,
    });
    try runTrace(.{
        .seed = 0xfeed_f00d,
        .doc_count = 5,
        .op_count = 160,
    });
    try runTrace(.{
        .seed = 0x5eed_0008,
        .doc_count = 8,
        .op_count = 180,
    });
}

test "delete-only update can arrive before inserted structs in trace harness" {
    var docs = [_]mirage.Doc{
        mirage.Doc.init(std.testing.allocator, 9001),
        mirage.Doc.init(std.testing.allocator, 9002),
    };
    defer for (&docs) |*doc| doc.deinit();

    try docs[0].text().insert(0, "abcdef");
    const after_insert_state = try docs[0].text().encodeStateVector(std.testing.allocator);
    defer std.testing.allocator.free(after_insert_state);
    const insert_update = try docs[0].text().encodeStateAsUpdate(std.testing.allocator, null);
    defer std.testing.allocator.free(insert_update);

    try docs[0].text().delete(2, 2);
    const delete_only_update = try docs[0].text().encodeStateAsUpdate(std.testing.allocator, after_insert_state);
    defer std.testing.allocator.free(delete_only_update);

    try docs[1].text().applyUpdate(delete_only_update);
    try std.testing.expectEqual(@as(usize, 1), mirage.debug.pendingUpdateCount(docs[1].text()));
    try docs[1].text().applyUpdate(insert_update);
    try std.testing.expectEqual(@as(usize, 0), mirage.debug.pendingUpdateCount(docs[1].text()));

    try finalFullSync(&docs);
    try expectConverged(&docs);
}

const TraceConfig = struct {
    seed: u64,
    doc_count: usize,
    op_count: usize,
};

fn runTrace(config: TraceConfig) TraceError!void {
    const docs = try std.testing.allocator.alloc(mirage.Doc, config.doc_count);
    defer std.testing.allocator.free(docs);
    for (docs, 0..) |*doc, index| {
        doc.* = mirage.Doc.init(std.testing.allocator, 10_000 + @as(mirage.ClientId, @intCast(index)));
    }
    defer for (docs) |*doc| doc.deinit();

    var ops: std.ArrayList(TraceOp) = .empty;
    defer ops.deinit(std.testing.allocator);

    var rng = std.Random.DefaultPrng.init(config.seed);
    const random = rng.random();

    var step: usize = 0;
    while (step < config.op_count) : (step += 1) {
        const op = chooseOp(random, docs);
        try ops.append(std.testing.allocator, op);
        applyTraceOp(docs, op) catch |err| {
            printTrace(config.seed, ops.items);
            return err;
        };
        checkAllIntegrity(docs) catch |err| {
            printTrace(config.seed, ops.items);
            return err;
        };
    }

    finalFullSync(docs) catch |err| {
        printTrace(config.seed, ops.items);
        return err;
    };
    expectConverged(docs) catch |err| {
        printTrace(config.seed, ops.items);
        return err;
    };
}

fn chooseOp(random: std.Random, docs: []mirage.Doc) TraceOp {
    const doc_index = random.uintLessThan(usize, docs.len);
    const text = docs[doc_index].text();
    const roll = random.uintLessThan(u8, 100);

    if (roll < 30 or text.len() == 0) {
        return .{
            .tag = .insert,
            .doc = doc_index,
            .index = random.uintLessThan(mirage.Clock, text.len() + 1),
            .text = randomChar(random),
        };
    }
    if (roll < 44) {
        return .{
            .tag = .insert_attrs,
            .doc = doc_index,
            .index = random.uintLessThan(mirage.Clock, text.len() + 1),
            .text = randomChar(random),
            .attr_key = randomAttrKey(random),
            .attr_value = randomSetAttrValue(random),
        };
    }
    if (roll < 58 and text.len() > 0) {
        const index = random.uintLessThan(mirage.Clock, text.len());
        return .{
            .tag = .delete,
            .doc = doc_index,
            .index = index,
            .len = 1 + random.uintLessThan(mirage.Clock, @min(@as(mirage.Clock, 3), text.len() - index)),
        };
    }
    if (roll < 70 and text.len() > 0) {
        const index = random.uintLessThan(mirage.Clock, text.len());
        return .{
            .tag = .format,
            .doc = doc_index,
            .index = index,
            .len = 1 + random.uintLessThan(mirage.Clock, text.len() - index),
            .attr_key = randomAttrKey(random),
            .attr_value = randomAttrValue(random),
        };
    }

    const other_doc = randomOtherDoc(random, docs.len, doc_index);
    return .{
        .tag = switch (random.uintLessThan(u8, 4)) {
            0 => .send_full,
            1 => .send_diff,
            2 => .send_stale_diff,
            else => .duplicate_full,
        },
        .doc = doc_index,
        .other_doc = other_doc,
    };
}

fn applyTraceOp(docs: []mirage.Doc, op: TraceOp) TraceError!void {
    const text = docs[op.doc].text();
    switch (op.tag) {
        .insert => try text.insert(op.index, (&[_]u8{op.text})[0..]),
        .insert_attrs => {
            const attr = mirage.Attribute{
                .key = op.attr_key.bytes(),
                .value = op.attr_value.value(),
            };
            try text.insertWithAttrs(op.index, (&[_]u8{op.text})[0..], &.{attr});
        },
        .delete => try text.delete(op.index, op.len),
        .format => {
            const attr = mirage.Attribute{
                .key = op.attr_key.bytes(),
                .value = op.attr_value.value(),
            };
            try text.format(op.index, op.len, &.{attr});
        },
        .send_full => try sendUpdate(docs, op.doc, op.other_doc, null, false),
        .send_diff => {
            const state = try docs[op.other_doc].text().encodeStateVector(std.testing.allocator);
            defer std.testing.allocator.free(state);
            try sendUpdate(docs, op.doc, op.other_doc, state, false);
        },
        .send_stale_diff => {
            const state = try encodeStaleStateVector(docs[op.doc].text(), std.testing.allocator);
            defer std.testing.allocator.free(state);
            try sendUpdate(docs, op.doc, op.other_doc, state, false);
        },
        .duplicate_full => try sendUpdate(docs, op.doc, op.other_doc, null, true),
    }
}

fn sendUpdate(
    docs: []mirage.Doc,
    from: usize,
    to: usize,
    state_vector: ?[]const u8,
    duplicate: bool,
) TraceError!void {
    const update = try docs[from].text().encodeStateAsUpdate(std.testing.allocator, state_vector);
    defer std.testing.allocator.free(update);

    try docs[to].text().applyUpdate(update);
    if (duplicate) try docs[to].text().applyUpdate(update);
}

fn finalFullSync(docs: []mirage.Doc) TraceError!void {
    var round: usize = 0;
    while (round < docs.len) : (round += 1) {
        for (docs, 0..) |*from, from_index| {
            const update = try from.text().encodeStateAsUpdate(std.testing.allocator, null);
            defer std.testing.allocator.free(update);
            for (docs, 0..) |*to, to_index| {
                if (from_index != to_index) try to.text().applyUpdate(update);
            }
        }
    }
}

fn expectConverged(docs: []mirage.Doc) TraceError!void {
    const expected = try docs[0].text().toOwnedString(std.testing.allocator, null);
    defer std.testing.allocator.free(expected);

    for (docs) |*doc| {
        const rendered = try doc.text().toOwnedString(std.testing.allocator, null);
        defer std.testing.allocator.free(rendered);
        if (!std.mem.eql(u8, expected, rendered)) return error.Diverged;
        if (mirage.debug.pendingUpdateCount(doc.text()) != 0) return error.PendingUpdatesRemain;
        try mirage.debug.checkIntegrity(doc.text());
    }
}

fn checkAllIntegrity(docs: []mirage.Doc) TraceError!void {
    for (docs) |*doc| {
        try mirage.debug.checkIntegrity(doc.text());
    }
}

fn encodeStaleStateVector(text: *mirage.Text, allocator: std.mem.Allocator) TraceError![]u8 {
    var enc = mirage.encoding.Encoder.init(allocator);
    errdefer enc.deinit();

    const known = mirage.debug.clientState(text, 10_000);
    try enc.writeVarU64(1);
    try enc.writeVarU64(10_000);
    try enc.writeVarU64(if (known > 0) known - 1 else 0);
    return try enc.toOwnedSlice();
}

fn randomOtherDoc(random: std.Random, doc_count: usize, doc_index: usize) usize {
    if (doc_count == 1) return doc_index;
    const offset = 1 + random.uintLessThan(usize, doc_count - 1);
    return (doc_index + offset) % doc_count;
}

fn randomChar(random: std.Random) u8 {
    const alphabet = "abcdefghijklmnopqrstuvwxyz";
    return alphabet[random.uintLessThan(usize, alphabet.len)];
}

fn randomAttrKey(random: std.Random) AttrKey {
    return switch (random.uintLessThan(u8, 3)) {
        0 => .bold,
        1 => .color,
        else => .source,
    };
}

fn randomSetAttrValue(random: std.Random) AttrValue {
    return switch (random.uintLessThan(u8, 3)) {
        0 => .true_value,
        1 => .red,
        else => .trace,
    };
}

fn randomAttrValue(random: std.Random) AttrValue {
    return switch (random.uintLessThan(u8, 4)) {
        0 => .null,
        1 => .true_value,
        2 => .red,
        else => .trace,
    };
}

fn printTrace(seed: u64, ops: []const TraceOp) void {
    std.debug.print("failing trace seed=0x{x}, ops={d}\n", .{ seed, ops.len });
    for (ops, 0..) |op, index| {
        std.debug.print("{d}: {s} doc={d}", .{ index, @tagName(op.tag), op.doc });
        switch (op.tag) {
            .insert, .insert_attrs => {
                std.debug.print(" index={d} text='{c}'", .{ op.index, op.text });
            },
            .delete, .format => {
                std.debug.print(" index={d} len={d}", .{ op.index, op.len });
            },
            .send_full, .send_diff, .send_stale_diff, .duplicate_full => {
                std.debug.print(" to={d}", .{op.other_doc});
            },
        }
        switch (op.tag) {
            .insert_attrs, .format => {
                std.debug.print(" attr={s}:{s}", .{ @tagName(op.attr_key), @tagName(op.attr_value) });
            },
            else => {},
        }
        std.debug.print("\n", .{});
    }
}
