const std = @import("std");
const id = @import("id.zig");
const text_mod = @import("text.zig");

pub const Doc = struct {
    text_value: text_mod.Text,

    /// Creates one replicated text document for `client_id`.
    /// The allocator is retained by the contained text value until `deinit`.
    pub fn init(allocator: std.mem.Allocator, client_id: id.ClientId) Doc {
        return .{
            .text_value = text_mod.Text.init(allocator, client_id),
        };
    }

    /// Frees all storage owned by the document.
    pub fn deinit(self: *Doc) void {
        self.text_value.deinit();
        self.* = undefined;
    }

    /// Returns the document text CRDT.
    pub fn text(self: *Doc) *text_mod.Text {
        return &self.text_value;
    }
};

test "Doc init and deinit" {
    const allocator = std.testing.allocator;
    var doc = Doc.init(allocator, 1);
    defer doc.deinit();
    try std.testing.expectEqual(1, doc.text().impl.client_id);
}
