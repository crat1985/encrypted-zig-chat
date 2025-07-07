const std = @import("std");
const socket = @import("socket.zig");

pub fn auth(derived_passphrase: [32]u8) !std.crypto.dh.X25519.KeyPair {
    const ed_key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(derived_passphrase);

    const reader_lock = socket.reader.lock();
    defer reader_lock.unlock();

    const writer_lock = socket.writer.lock();
    defer writer_lock.unlock();

    //Send the public Ed key
    try writer_lock.data.writeAll(&ed_key_pair.public_key.toBytes());

    //Read the challenge
    const challenge = try reader_lock.data.readBytesNoEof(64);

    const signature = try ed_key_pair.sign(&challenge, null);
    const signature_bytes: [64]u8 = signature.toBytes();

    //Send signature
    try writer_lock.data.writeAll(&signature_bytes);

    {
        const res = try reader_lock.data.readByte();
        if (res != 0) return error.InvalidRes;
    }

    return try std.crypto.dh.X25519.KeyPair.fromEd25519(ed_key_pair);
}
