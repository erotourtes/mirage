const public = @import("text/public.zig");
const impl = @import("text/impl.zig");

pub const Text = public.Text;
pub const TextImpl = impl.TextImpl;
pub const TextError = impl.TextError;
pub const debug = public.debug;
