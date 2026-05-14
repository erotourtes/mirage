const std = @import("std");
const builtin = @import("builtin");
const mirage = @import("mirage_lib");

const ErrorCode = enum(u32) {
    ok = 0,
    out_of_memory = 1,
    invalid_handle = 2,
    invalid_input = 3,
    operation_failed = 4,
};

export fn alloc(len: usize) usize {
    const bytes = allocator().alloc(u8, len) catch return 0;
    return @intFromPtr(bytes.ptr);
}

export fn free(ptr: usize, len: usize) void {
    if (ptr == 0 or len == 0) return;
    allocator().free(asBytes(ptr, len));
}

export fn doc_create(client_id: u64, out_doc_addr: usize) u32 {
    if (out_doc_addr == 0) return fail(.invalid_input);
    writeUsize(out_doc_addr, 0);

    const doc = allocator().create(mirage.Doc) catch return fail(.out_of_memory);
    doc.* = mirage.Doc.init(allocator(), client_id);
    writeUsize(out_doc_addr, @intFromPtr(doc));
    return ok();
}

export fn doc_destroy(doc_handle: usize) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    doc.deinit();
    allocator().destroy(doc);
    return ok();
}

export fn text_len(doc_handle: usize, out_len_addr: usize) u32 {
    if (out_len_addr == 0) return fail(.invalid_input);
    writeU64(out_len_addr, 0);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    writeU64(out_len_addr, doc.text().len());
    return ok();
}

export fn text_current_revision(doc_handle: usize, out_revision_addr: usize) u32 {
    if (out_revision_addr == 0) return fail(.invalid_input);
    writeU64(out_revision_addr, 0);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    writeU64(out_revision_addr, doc.text().currentRevision());
    return ok();
}

export fn text_history_len(doc_handle: usize, out_revision_addr: usize) u32 {
    if (out_revision_addr == 0) return fail(.invalid_input);
    writeU64(out_revision_addr, 0);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    writeU64(out_revision_addr, doc.text().historyLen());
    return ok();
}

export fn text_internal_byte_len(doc_handle: usize, out_len_addr: usize) u32 {
    if (out_len_addr == 0) return fail(.invalid_input);
    writeU64(out_len_addr, 0);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    writeU64(out_len_addr, @intCast(doc.text().internalByteLen()));
    return ok();
}

export fn text_visible_byte_len(doc_handle: usize, revision: u64, revision_is_null: u32, out_len_addr: usize) u32 {
    if (out_len_addr == 0) return fail(.invalid_input);
    writeU64(out_len_addr, 0);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const target_revision: ?u64 = if (revision_is_null != 0) null else revision;
    writeU64(out_len_addr, @intCast(doc.text().visibleByteLen(target_revision)));
    return ok();
}

export fn text_insert(doc_handle: usize, index: u64, ptr: usize, len: usize) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const text = inputBytes(ptr, len) catch return fail(.invalid_input);
    doc.text().insert(index, text) catch return fail(.operation_failed);
    return ok();
}

export fn text_insert_attr(
    doc_handle: usize,
    index: u64,
    text_ptr: usize,
    text_len_bytes: usize,
    key_ptr: usize,
    key_len: usize,
    value_ptr: usize,
    value_len: usize,
    value_is_null: u32,
) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const text = inputBytes(text_ptr, text_len_bytes) catch return fail(.invalid_input);
    const attribute = singleAttribute(key_ptr, key_len, value_ptr, value_len, value_is_null) catch return fail(.invalid_input);
    doc.text().insertWithAttrs(index, text, &.{attribute}) catch return fail(.operation_failed);
    return ok();
}

export fn text_format(
    doc_handle: usize,
    index: u64,
    len: u64,
    key_ptr: usize,
    key_len: usize,
    value_ptr: usize,
    value_len: usize,
    value_is_null: u32,
) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const attribute = singleAttribute(key_ptr, key_len, value_ptr, value_len, value_is_null) catch return fail(.invalid_input);
    doc.text().format(index, len, &.{attribute}) catch return fail(.operation_failed);
    return ok();
}

export fn text_delete(doc_handle: usize, index: u64, len: u64) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    doc.text().delete(index, len) catch return fail(.operation_failed);
    return ok();
}

export fn text_compact(doc_handle: usize) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    doc.text().compact() catch return fail(.operation_failed);
    return ok();
}

export fn text_to_string(doc_handle: usize, out_ptr_addr: usize, out_len_addr: usize) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const rendered = doc.text().toOwnedString(allocator(), null) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, rendered);
    return ok();
}

export fn text_to_string_revision(doc_handle: usize, revision: u64, out_ptr_addr: usize, out_len_addr: usize) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const rendered = doc.text().toOwnedString(allocator(), revision) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, rendered);
    return ok();
}

export fn text_to_delta(doc_handle: usize, out_ptr_addr: usize, out_len_addr: usize) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    var delta = doc.text().toDelta(allocator(), null) catch return fail(.operation_failed);
    defer delta.deinit(allocator());

    const rendered = deltaToJson(allocator(), &delta) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, rendered);
    return ok();
}

export fn text_to_delta_revision(doc_handle: usize, revision: u64, out_ptr_addr: usize, out_len_addr: usize) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    var delta = doc.text().toDelta(allocator(), revision) catch return fail(.operation_failed);
    defer delta.deinit(allocator());

    const rendered = deltaToJson(allocator(), &delta) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, rendered);
    return ok();
}

export fn text_to_delta_range(
    doc_handle: usize,
    start: u64,
    end: u64,
    revision: u64,
    revision_is_null: u32,
    include_leading_attrs: u32,
    out_ptr_addr: usize,
    out_len_addr: usize,
) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const target_revision: ?u64 = if (revision_is_null != 0) null else revision;
    var delta = doc.text().toDeltaRange(
        allocator(),
        start,
        end,
        target_revision,
        include_leading_attrs != 0,
    ) catch return fail(.operation_failed);
    defer delta.deinit(allocator());

    const rendered = deltaToJson(allocator(), &delta) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, rendered);
    return ok();
}

export fn text_encode_state_vector(doc_handle: usize, out_ptr_addr: usize, out_len_addr: usize) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const state_vector = doc.text().encodeStateVector(allocator()) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, state_vector);
    return ok();
}

export fn text_encode_update(
    doc_handle: usize,
    state_ptr: usize,
    state_len: usize,
    out_ptr_addr: usize,
    out_len_addr: usize,
) u32 {
    clearResult(out_ptr_addr, out_len_addr) catch return fail(.invalid_input);

    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const state_vector: ?[]const u8 = if (state_ptr == 0 and state_len == 0)
        null
    else
        inputBytes(state_ptr, state_len) catch return fail(.invalid_input);
    const update = doc.text().encodeStateAsUpdate(allocator(), state_vector) catch return fail(.operation_failed);
    writeResult(out_ptr_addr, out_len_addr, update);
    return ok();
}

export fn text_apply_update(doc_handle: usize, update_ptr: usize, update_len: usize) u32 {
    const doc = asDoc(doc_handle) orelse return fail(.invalid_handle);
    const update = inputBytes(update_ptr, update_len) catch return fail(.invalid_input);
    doc.text().applyUpdate(update) catch return fail(.operation_failed);
    return ok();
}

fn allocator() std.mem.Allocator {
    comptime {
        const arch = builtin.target.cpu.arch;
        std.debug.assert(arch == .wasm32 or arch == .wasm64);
    }
    return std.heap.wasm_allocator;
}

fn asDoc(handle: usize) ?*mirage.Doc {
    if (handle == 0) return null;
    const doc: *mirage.Doc = @ptrFromInt(handle);
    return doc;
}

fn asBytes(ptr: usize, len: usize) []u8 {
    const bytes: [*]u8 = @ptrFromInt(ptr);
    return bytes[0..len];
}

fn asConstBytes(ptr: usize, len: usize) []const u8 {
    const bytes: [*]const u8 = @ptrFromInt(ptr);
    return bytes[0..len];
}

fn inputBytes(ptr: usize, len: usize) ![]const u8 {
    if (len == 0) return &.{};
    if (ptr == 0) return error.InvalidInput;
    return asConstBytes(ptr, len);
}

fn singleAttribute(
    key_ptr: usize,
    key_len: usize,
    value_ptr: usize,
    value_len: usize,
    value_is_null: u32,
) !mirage.Attribute {
    return .{
        .key = try inputBytes(key_ptr, key_len),
        .value = if (value_is_null != 0)
            .null
        else
            .{ .string = try inputBytes(value_ptr, value_len) },
    };
}

fn deltaToJson(alloc_instance: std.mem.Allocator, delta: *const mirage.Delta) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc_instance);

    try out.append(alloc_instance, '[');
    for (delta.ops.items, 0..) |op, op_index| {
        if (op_index > 0) try out.append(alloc_instance, ',');
        try out.appendSlice(alloc_instance, "{\"insert\":");
        try appendJsonString(&out, alloc_instance, op.insert);

        var has_attributes = false;
        for (op.attributes) |attribute| {
            if (attribute.value == .string) {
                has_attributes = true;
                break;
            }
        }

        if (has_attributes) {
            try out.appendSlice(alloc_instance, ",\"attributes\":{");
            var first_attribute = true;
            for (op.attributes) |attribute| {
                switch (attribute.value) {
                    .null => {},
                    .string => |value| {
                        if (!first_attribute) try out.append(alloc_instance, ',');
                        first_attribute = false;
                        try appendJsonString(&out, alloc_instance, attribute.key);
                        try out.append(alloc_instance, ':');
                        try appendJsonString(&out, alloc_instance, value);
                    },
                }
            }
            try out.append(alloc_instance, '}');
        }

        try out.append(alloc_instance, '}');
    }
    try out.append(alloc_instance, ']');

    return try out.toOwnedSlice(alloc_instance);
}

fn appendJsonString(out: *std.ArrayList(u8), alloc_instance: std.mem.Allocator, value: []const u8) !void {
    const hex = "0123456789abcdef";

    try out.append(alloc_instance, '"');
    for (value) |byte| {
        if (byte < 0x20) {
            switch (byte) {
                0x08 => try out.appendSlice(alloc_instance, "\\b"),
                0x0c => try out.appendSlice(alloc_instance, "\\f"),
                '\n' => try out.appendSlice(alloc_instance, "\\n"),
                '\r' => try out.appendSlice(alloc_instance, "\\r"),
                '\t' => try out.appendSlice(alloc_instance, "\\t"),
                else => {
                    try out.appendSlice(alloc_instance, "\\u00");
                    try out.append(alloc_instance, hex[byte >> 4]);
                    try out.append(alloc_instance, hex[byte & 0x0f]);
                },
            }
        } else {
            switch (byte) {
                '"' => try out.appendSlice(alloc_instance, "\\\""),
                '\\' => try out.appendSlice(alloc_instance, "\\\\"),
                else => try out.append(alloc_instance, byte),
            }
        }
    }
    try out.append(alloc_instance, '"');
}

fn clearResult(out_ptr_addr: usize, out_len_addr: usize) !void {
    if (out_ptr_addr == 0 or out_len_addr == 0) return error.InvalidOutput;
    writeUsize(out_ptr_addr, 0);
    writeUsize(out_len_addr, 0);
}

fn writeResult(out_ptr_addr: usize, out_len_addr: usize, bytes: []const u8) void {
    writeUsize(out_ptr_addr, @intFromPtr(bytes.ptr));
    writeUsize(out_len_addr, bytes.len);
}

fn writeUsize(out_addr: usize, value: usize) void {
    const out: *usize = @ptrFromInt(out_addr);
    out.* = value;
}

fn writeU64(out_addr: usize, value: u64) void {
    const out: *u64 = @ptrFromInt(out_addr);
    out.* = value;
}

fn ok() u32 {
    return @intFromEnum(ErrorCode.ok);
}

fn fail(code: ErrorCode) u32 {
    return @intFromEnum(code);
}
