const std = @import("std");

pub const salt: [16]u8 = .{ 112, 63, 240, 11, 151, 170, 17, 12, 168, 88, 154, 97, 28, 144, 121, 19 };

pub fn derive(source: []u8) ![32]u8 {
    var derived: [32]u8 = undefined;
    try std.crypto.pwhash.argon2.kdf(std.heap.page_allocator, &derived, source, &salt, .owasp_2id, .argon2id);
    return derived;
}
