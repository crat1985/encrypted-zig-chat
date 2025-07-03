const std = @import("std");
const Int = @import("int.zig");

pub const BLOCK_SIZE = 400;

const allocator = std.heap.page_allocator;

const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

/// * Block count of the encrypted part (4 bytes) (clear)
/// * Target ID (32 bytes) (clear)
/// * Nonce (12 bytes) (clear)
/// * Tag (16 bytes) (clear)
/// * Encrypted message
///     * Real size of the payload in bytes (8 bytes)
///     * Actual payload
///     * Padding
pub fn encrypt_message_and_send(writer: std.io.AnyWriter, symmetric_key: [32]u8, target_id: [32]u8, msg: []const u8) !void {
    const block_count: u32 = blk: {
        const encrypted_msg_len = @sizeOf(u64) + msg.len;

        break :blk @intCast((encrypted_msg_len + (BLOCK_SIZE - 1)) / BLOCK_SIZE);
    };

    const encrypted_size = @as(u64, block_count) * BLOCK_SIZE;

    const nonce = blk: {
        var nonce: [12]u8 = undefined;

        std.crypto.random.bytes(&nonce);

        break :blk nonce;
    };

    const encrypted = try allocator.alloc(u8, encrypted_size);
    defer allocator.free(encrypted);
    const unencrypted_part = try allocator.alloc(u8, encrypted_size);
    defer allocator.free(unencrypted_part);
    {
        Int.writeInt(u64, msg.len, unencrypted_part[0..8], .big);
        @memcpy(unencrypted_part[8 .. 8 + msg.len], msg);
        std.crypto.random.bytes(unencrypted_part[8 + msg.len ..]);
    }

    var tag: [ChaCha20Poly1305.tag_length]u8 = undefined;

    ChaCha20Poly1305.encrypt(encrypted, &tag, unencrypted_part, &.{}, nonce, symmetric_key);

    try writer.writeInt(u32, block_count, .big);
    try writer.writeAll(&target_id);

    try writer.writeAll(&nonce);
    try writer.writeAll(&tag);
    try writer.writeAll(encrypted);
}

/// * ~~Block count of the encrypted part (4 bytes) (clear)~~
/// * ~~From (32 bytes)~~
/// * ~~*DM ID (0 or 32 bytes) (only if `From` == me)*~~
/// * Nonce (12 bytes) (clear)
/// * Tag (16 bytes) (clear)
/// * Encrypted message
///     * Real size of the payload in bytes (8 bytes)
///     * Actual payload
///     * Padding
pub fn decrypt_message(block_count: u32, privkey: [32]u8, other_pubkey: std.crypto.ecc.Curve25519, reader: std.io.AnyReader) ![]u8 {
    const symmetric_key = try @import("../client.zig").get_symmetric_key(other_pubkey, privkey);

    const nonce = try reader.readBytesNoEof(12);
    const tag = try reader.readBytesNoEof(16);

    const total_encrypted_len = @as(u64, block_count) * BLOCK_SIZE;

    std.debug.print("Total encrypted length = {d}\n", .{total_encrypted_len});

    const encrypted = try allocator.alloc(u8, total_encrypted_len);
    defer allocator.free(encrypted);
    try reader.readNoEof(encrypted);

    const decrypted = try allocator.alloc(u8, total_encrypted_len);
    defer allocator.free(decrypted);
    try ChaCha20Poly1305.decrypt(decrypted, encrypted, tag, &.{}, nonce, symmetric_key);

    const payload_size = blk: {
        const payload_size_bytes = decrypted[0..8].*;
        break :blk std.mem.readInt(u64, &payload_size_bytes, .big);
    };

    const payload = try allocator.dupe(u8, decrypted[8 .. 8 + payload_size]);

    return payload;
}
