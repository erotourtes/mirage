pub const ClientId = u64;
pub const Clock = u64;

pub const Id = struct {
    client: ClientId,
    clock: Clock,

    pub fn check_if_eql(a: Id, b: Id) bool {
        return a.client == b.client and a.clock == b.clock;
    }
};

pub fn check_if_id_eql(a: ?Id, b: ?Id) bool {
    if (a == null and b == null) {
        return true;
    }
    const left = a orelse return false;
    const right = b orelse return false;
    return left.check_if_eql(right);
}

const expect = @import("std").testing.expect;

test "check_if_id_eql returns true for equal non-null ids" {
    const id1 = Id{ .client = 1, .clock = 2 };
    const id2 = Id{ .client = 1, .clock = 2 };
    try expect(check_if_id_eql(id1, id2));
}

test "check_if_id_eql returns false for different non-null ids" {
    const id1 = Id{ .client = 1, .clock = 2 };
    const id2 = Id{ .client = 1, .clock = 3 };
    try expect(!check_if_id_eql(id1, id2));
}

test "check_if_id_eql returns false if one id is null" {
    const id1 = Id{ .client = 1, .clock = 2 };
    try expect(!check_if_id_eql(id1, null));
    try expect(!check_if_id_eql(null, id1));
}

test "check_if_id_eql returns true if both ids are null" {
    try expect(check_if_id_eql(null, null));
}
