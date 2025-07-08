const std = @import("std");

const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

pub fn generate_msg_id() u64 {
    const t: u64 = @as(u32, @bitCast(@as(i32, @truncate(std.time.timestamp()))));
    const rand = std.crypto.random.int(u32);
    return (t << 33) | rand;
}

pub fn mkdir_if_absent(dir: std.fs.Dir, sub_dir: []const u8) !std.fs.Dir {
    dir.makeDir(sub_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    return try dir.openDir(sub_dir, .{});
}

pub const CHACHA_DATA_LENGTH = ChaCha20Poly1305.nonce_length + ChaCha20Poly1305.tag_length;

pub fn encrypt_chacha(comptime n: usize, source: *const [n]u8, symmetric_key: [32]u8) [n + CHACHA_DATA_LENGTH]u8 {
    var encrypted: [n + CHACHA_DATA_LENGTH]u8 = undefined;

    const nonce = blk: {
        var nonce: [12]u8 = undefined;

        std.crypto.random.bytes(&nonce);

        break :blk nonce;
    };

    var tag: [ChaCha20Poly1305.tag_length]u8 = undefined;

    ChaCha20Poly1305.encrypt(encrypted[CHACHA_DATA_LENGTH..], &tag, source, &.{}, nonce, symmetric_key);

    return encrypted;
}

pub fn decrypt_chacha(comptime n: usize, source: *const [n]u8, symmetric_key: [32]u8) ![n - CHACHA_DATA_LENGTH]u8 {
    var decrypted: [n - CHACHA_DATA_LENGTH]u8 = undefined;

    const nonce: [ChaCha20Poly1305.nonce_length]u8 = source.*[0..ChaCha20Poly1305.nonce_length].*;

    const tag: [ChaCha20Poly1305.tag_length]u8 = source.*[ChaCha20Poly1305.nonce_length..CHACHA_DATA_LENGTH].*;

    try ChaCha20Poly1305.decrypt(&decrypted, source, tag, &.{}, nonce, symmetric_key);

    return decrypted;
}
