pub const ClientId = u64;

/// A CRDT clock within a single client's operation history.
pub const Clock = u64;

/// A visible Unicode scalar index in the text document.
pub const TextIndex = u64;

/// A visible Unicode scalar length in the text document.
pub const TextLen = u64;

pub const Id = struct {
    client: ClientId,
    clock: Clock,

    pub fn checkIfEql(a: Id, b: Id) bool {
        return a.client == b.client and a.clock == b.clock;
    }
};

pub fn checkIfIdEql(a: ?Id, b: ?Id) bool {
    if (a == null and b == null) {
        return true;
    }
    const left = a orelse return false;
    const right = b orelse return false;
    return left.checkIfEql(right);
}

const expect = @import("std").testing.expect;

test "checkIfIdEql returns true for equal non-null ids" {
    const id1 = Id{ .client = 1, .clock = 2 };
    const id2 = Id{ .client = 1, .clock = 2 };
    try expect(checkIfIdEql(id1, id2));
}

test "checkIfIdEql returns false for different non-null ids" {
    const id1 = Id{ .client = 1, .clock = 2 };
    const id2 = Id{ .client = 1, .clock = 3 };
    try expect(!checkIfIdEql(id1, id2));
}

test "checkIfIdEql returns false if one id is null" {
    const id1 = Id{ .client = 1, .clock = 2 };
    try expect(!checkIfIdEql(id1, null));
    try expect(!checkIfIdEql(null, id1));
}

test "checkIfIdEql returns true if both ids are null" {
    try expect(checkIfIdEql(null, null));
}
