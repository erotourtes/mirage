const std = @import("std");
const id = @import("../id.zig");
const item_mod = @import("../item.zig");
const attrs = @import("../attrs.zig");
const debug_mod = @import("../debug.zig");
const impl_mod = @import("impl.zig");
const debug_view = @import("debug_view.zig");

pub const TextError = impl_mod.TextError;
pub const TextImpl = impl_mod.TextImpl;

/// One replicated text CRDT document.
///
/// Public indexes are Unicode scalar indexes over valid UTF-8 text. Returned
/// byte slices and deltas that take an allocator are owned by the caller unless
/// the function states otherwise.
pub const Text = struct {
    /// Implementation storage. Prefer the methods on `Text`; this field exists
    /// so `Text` can keep value semantics without heap-allocating its body.
    impl: TextImpl,

    /// Creates an empty text document for `client_id`.
    ///
    /// The allocator is retained by the document and used for all internal
    /// storage until `deinit` is called.
    pub fn init(allocator: std.mem.Allocator, client_id: id.ClientId) Text {
        return .{ .impl = TextImpl.init(allocator, client_id) };
    }

    /// Frees all storage owned by this text document.
    pub fn deinit(self: *Text) void {
        self.impl.deinit();
        self.* = undefined;
    }

    /// Returns the visible document length in Unicode scalar values.
    pub fn len(self: *const Text) id.TextLen {
        return self.impl.len();
    }

    /// Returns the latest document-local history revision.
    pub fn currentRevision(self: *const Text) id.Revision {
        return self.impl.currentRevision();
    }

    /// Returns the number of document-local history revisions.
    pub fn historyLen(self: *const Text) id.Revision {
        return self.impl.historyLen();
    }

    /// Returns the byte length of Mirage's current internal representation.
    ///
    /// This is computed by the implementation itself rather than estimated by
    /// callers, so it should be updated alongside storage changes.
    pub fn internalByteLen(self: *const Text) usize {
        return self.impl.internalByteLen();
    }

    /// Returns the visible UTF-8 text byte length.
    pub fn visibleByteLen(self: *const Text, revision: ?id.Revision) usize {
        return self.impl.visibleByteLen(revision);
    }

    /// Inserts valid UTF-8 bytes at `index`.
    ///
    /// `index` is a Unicode scalar index. Empty text is a no-op. `bytes` are
    /// copied into the document before this function returns.
    pub fn insert(self: *Text, index: id.TextIndex, bytes: []const u8) TextError!void {
        try self.impl.insert(index, bytes);
    }

    /// Inserts valid UTF-8 bytes with formatting attributes at `index`.
    ///
    /// Attribute keys and string values are copied into the document. Attribute
    /// values support only `null` and string values.
    pub fn insertWithAttrs(
        self: *Text,
        index: id.TextIndex,
        bytes: []const u8,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        try self.impl.insertWithAttrs(index, bytes, attributes);
    }

    /// Applies formatting attributes to an existing visible range.
    ///
    /// `index` and `format_len` are Unicode scalar units. A `null` attribute
    /// value clears that attribute over the formatted range.
    pub fn format(
        self: *Text,
        index: id.TextIndex,
        format_len: id.TextLen,
        attributes: []const attrs.Attribute,
    ) TextError!void {
        try self.impl.format(index, format_len, attributes);
    }

    /// Deletes `delete_len` visible Unicode scalars starting at `index`.
    pub fn delete(self: *Text, index: id.TextIndex, delete_len: id.TextLen) TextError!void {
        try self.impl.delete(index, delete_len);
    }

    /// Prunes redundant formatting markers and joins safe adjacent text structs.
    ///
    /// Editing operations do not run this automatically; call it when a cleaner
    /// internal structure is worth the extra work. Historical snapshots before
    /// compaction are not guaranteed to remain exact after this runs.
    pub fn compact(self: *Text) TextError!void {
        try self.impl.compact();
    }

    /// Encodes this document's state vector.
    ///
    /// The returned byte slice is allocated with `allocator` and must be freed
    /// by the caller.
    pub fn encodeStateVector(self: *const Text, allocator: std.mem.Allocator) TextError![]u8 {
        return try self.impl.encodeStateVector(allocator);
    }

    /// Encodes an update from `encoded_target_state_vector` to the current state.
    ///
    /// Pass `null` to encode the whole document state. The returned byte slice
    /// is allocated with `allocator` and must be freed by the caller.
    pub fn encodeStateAsUpdate(
        self: *const Text,
        allocator: std.mem.Allocator,
        encoded_target_state_vector: ?[]const u8,
    ) TextError![]u8 {
        return try self.impl.encodeStateAsUpdate(allocator, encoded_target_state_vector);
    }

    /// Applies an update produced by `encodeStateAsUpdate`.
    ///
    /// Updates with missing dependencies are retained internally and retried
    /// after later successful updates.
    pub fn applyUpdate(self: *Text, update: []const u8) TextError!void {
        try self.impl.applyUpdate(update);
    }

    /// Renders the visible document text as owned UTF-8 bytes.
    ///
    /// Pass `null` for the current state, or a document-local revision returned
    /// by `currentRevision`/`historyLen` for a best-effort historical snapshot.
    ///
    /// The returned byte slice is allocated with `allocator` and must be freed
    /// by the caller.
    pub fn toOwnedString(
        self: *const Text,
        allocator: std.mem.Allocator,
        revision: ?id.Revision,
    ) TextError![]u8 {
        return try self.impl.toOwnedString(allocator, revision);
    }

    /// Renders the document as attributed insert operations.
    ///
    /// Pass `null` for the current state, or a document-local revision returned
    /// by `currentRevision`/`historyLen` for a best-effort historical snapshot.
    ///
    /// The returned delta owns all inserted strings and copied attributes. Call
    /// `Delta.deinit` with the same allocator when done.
    pub fn toDelta(
        self: *const Text,
        allocator: std.mem.Allocator,
        revision: ?id.Revision,
    ) TextError!attrs.Delta {
        return try self.impl.toDelta(allocator, revision);
    }

    /// Renders a visible text range as attributed insert operations.
    ///
    /// `start` and `end` are Unicode scalar indexes in the visible text at
    /// `revision`. When `include_leading_attrs` is false, formatting markers
    /// before `start` are ignored for faster viewport-only rendering.
    pub fn toDeltaRange(
        self: *const Text,
        allocator: std.mem.Allocator,
        start: id.TextIndex,
        end: id.TextIndex,
        revision: ?id.Revision,
        include_leading_attrs: bool,
    ) TextError!attrs.Delta {
        return try self.impl.toDeltaRange(allocator, start, end, revision, include_leading_attrs);
    }
};

pub const debug = struct {
    pub fn checkIntegrity(text: *const Text) TextError!void {
        try debug_mod.checkIntegrity(debug_view.fromImpl(&text.impl));
    }

    pub fn itemCount(text: *const Text) usize {
        return debug_mod.itemCount(debug_view.fromImpl(&text.impl));
    }

    pub fn itemLen(text: *const Text, index: usize) id.Clock {
        return debug_mod.itemLen(debug_view.fromImpl(&text.impl), index);
    }

    pub fn itemDeleted(text: *const Text, index: usize) bool {
        return debug_mod.itemDeleted(debug_view.fromImpl(&text.impl), index);
    }

    pub fn findHandleById(text: *const Text, target: id.Id) TextError!item_mod.ItemHandle {
        return try debug_mod.findHandleById(debug_view.fromImpl(&text.impl), target);
    }

    pub fn clientState(text: *const Text, client: id.ClientId) id.Clock {
        return debug_mod.clientState(debug_view.fromImpl(&text.impl), client);
    }

    pub fn pendingUpdateCount(text: *const Text) usize {
        return debug_mod.pendingUpdateCount(debug_view.fromImpl(&text.impl));
    }

    pub fn liveFormatMarkerCount(text: *const Text, key: []const u8, value: ?[]const u8) usize {
        return debug_mod.liveFormatMarkerCount(debug_view.fromImpl(&text.impl), key, value);
    }
};
