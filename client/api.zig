const std = @import("std");
const Mutex = @import("../mutex.zig").Mutex;

pub fn auth(stream: std.net.Stream, derived_passphrase: [32]u8) !std.crypto.dh.X25519.KeyPair {
    const ed_key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(derived_passphrase);

    const reader = stream.reader();
    const writer = stream.writer();

    //Send the public Ed key
    try writer.writeAll(&ed_key_pair.public_key.toBytes());

    //Read the challenge
    const challenge = try reader.readBytesNoEof(64);

    const signature = try ed_key_pair.sign(&challenge, null);
    const signature_bytes: [64]u8 = signature.toBytes();

    //Send signature
    try writer.writeAll(&signature_bytes);

    {
        const res = try reader.readByte();
        if (res != 0) return error.InvalidRes;
    }

    return try std.crypto.dh.X25519.KeyPair.fromEd25519(ed_key_pair);
}
