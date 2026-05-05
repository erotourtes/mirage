const id = @import("id.zig");
const item = @import("item.zig");
const store = @import("store.zig");
const text = @import("text.zig");
const doc = @import("doc.zig");
pub const encoding = @import("encoding.zig");
const delete_set = @import("delete_set.zig");
const attrs = @import("attrs.zig");

pub const ClientId = id.ClientId;
pub const Clock = id.Clock;
pub const Id = id.Id;

pub const ItemHandle = item.ItemHandle;

pub const Text = text.Text;
pub const Doc = doc.Doc;
pub const debug = text.debug;
pub const Attribute = attrs.Attribute;
pub const AttributeValue = attrs.AttributeValue;
pub const Delta = attrs.Delta;
pub const DeltaOp = attrs.DeltaOp;

test {
    _ = id;
    _ = item;
    _ = store;
    _ = text;
    _ = doc;
    _ = encoding;
    _ = delete_set;
    _ = attrs;
}
