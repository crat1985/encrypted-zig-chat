const std = @import("std");

pub const BLOCK_SIZE = 4000;

const allocator = std.heap.page_allocator;

/// * ~~Block count of the encrypted part (4 bytes) (clear)~~ (sent before, to ensure the user is connected)
/// * ~~Target ID (32 bytes) (clear)~~ (sent before, to ensure the user is connected)
/// * Nonce (32 bytes) (clear)
/// * Encrypted message
///     * Real size of the payload in bytes (8 bytes)
///     * Actual payload
pub fn encrypt_message(symmetric_key: [32]u8, msg: []const u8, target_id: [32]u8, block_count: u32) ![]u8 {
    const nonce = blk: {
        var nonce: [32]u8 = undefined;

        std.crypto.random.bytes(&nonce);

        break :blk nonce;
    };

    const total_encrypted_length = BLOCK_SIZE * block_count;

    const total_len = @sizeOf(u32) + target_id.len + nonce.len + total_encrypted_length;

    const total_message = try allocator.alloc(u8, total_len);

    var i: usize = 0;

    {
        var block_count_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &block_count_bytes, block_count, .big);
        @memcpy(total_message[0..4], &block_count_bytes);
        i += 4;
    }

    {
        @memcpy(total_message[i .. i + target_id.len], &target_id);
        i += 32;
    }

    {
        @memcpy(total_message[i .. i + nonce.len], &nonce);
        i += nonce.len;
    }

    const temp_key = try get_temp_key(symmetric_key, nonce, total_encrypted_length);
    defer allocator.free(temp_key);

    const ENCRYPTED_MESSAGE_BEGINNING = @sizeOf(@TypeOf(block_count)) + target_id.len + nonce.len;

    {
        var real_size_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &real_size_bytes, msg.len, .big);
        @memcpy(total_message[i .. i + real_size_bytes.len], &real_size_bytes);
        i += real_size_bytes.len;
    }

    @memcpy(total_message[i .. i + msg.len], msg);
    i += msg.len;

    std.crypto.random.bytes(total_message[i..]);

    for (total_message[ENCRYPTED_MESSAGE_BEGINNING..], temp_key) |*c, key_c| {
        c.* ^= key_c;
    }

    return total_message;
}

/// * ~~Block count of the encrypted part (4 bytes) (clear)~~ (already read by the packet handler)
/// * ~~From (32 bytes)~~ (already read by the message listener)
/// * ~~*DM ID (0 or 32 bytes) (only if `From` == me)*~~ (already read by the message listener)
/// * Nonce (32 bytes) (clear)
/// * Encrypted message
///     * Real size of the payload in bytes (8 bytes)
///     * Actual payload
pub fn decrypt_message(symmetric_key: [32]u8, block_count: u32, reader: std.io.AnyReader) ![]u8 {
    const nonce = try reader.readBytesNoEof(32);

    const total_encrypted_len = 8 + @as(u64, block_count) * BLOCK_SIZE;

    const temp_key = try get_temp_key(symmetric_key, nonce, total_encrypted_len);
    defer allocator.free(temp_key);

    const payload_size = blk: {
        var payload_size_bytes = try reader.readBytesNoEof(8);

        for (&payload_size_bytes, temp_key[0..payload_size_bytes.len]) |*payload_size_c, key_c| {
            payload_size_c.* ^= key_c;
        }

        break :blk std.mem.readVarInt(u64, &payload_size_bytes, .big);
    };

    const decrypted_msg = try allocator.alloc(u8, payload_size);
    try reader.readNoEof(decrypted_msg);

    for (decrypted_msg, temp_key[8..]) |*decrypted_msg_ptr, key_c| {
        decrypted_msg_ptr.* ^= key_c;
    }

    return decrypted_msg;
}

pub fn get_temp_key(symmetric_key: [32]u8, nonce: [32]u8, size: usize) ![]u8 {
    const temp_key: []u8 = try allocator.alloc(u8, size);

    try std.crypto.pwhash.argon2.kdf(allocator, temp_key, &symmetric_key, &nonce, .owasp_2id, .argon2id);

    return temp_key;
}
