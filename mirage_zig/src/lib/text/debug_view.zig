const debug_mod = @import("../debug.zig");
const impl_mod = @import("impl.zig");

pub fn fromImpl(text: *const impl_mod.TextImpl) debug_mod.View {
    return .{
        .store = &text.store,
        .items = text.items.items,
        .bytes = text.bytes.items,
        .start = text.start,
        .end = text.end,
        .length = text.length,
        .pending_update_count = text.pending_updates.items.len,
    };
}
