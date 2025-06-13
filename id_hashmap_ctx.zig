const std = @import("std");

pub const HashMapContext = struct {
    const Self = @This();

    pub fn hash(_: Self, key: [32]u8) u64 {
        const Hasher = std.hash.Wyhash;

        var hasher = Hasher.init(0);
        hasher.update(&key);
        return hasher.final();
    }

    pub fn eql(_: Self, k1: [32]u8, k2: [32]u8) bool {
        return std.mem.eql(u8, &k1, &k2);
    }
};
