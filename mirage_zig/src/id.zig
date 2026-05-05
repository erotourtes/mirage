pub const ClientId = u64;
pub const Clock = u64;

pub const Id = struct {
    client: ClientId,
    clock: Clock,

    pub fn eql(a: Id, b: Id) bool {
        return a.client == b.client and a.clock == b.clock;
    }
};

pub fn idEql(a: ?Id, b: ?Id) bool {
    if (a) |left| {
        if (b) |right| return left.eql(right);
        return false;
    }
    return b == null;
}
