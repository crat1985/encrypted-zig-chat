const std = @import("std");

pub fn main() !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    const stream = try std.net.tcpConnectToAddress(addr);

    const x25519_key_pair = try handle_auth(stream);

    {
        const pubkey = x25519_key_pair.public_key;

        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    const stdout = std.io.getStdOut().writer();
    // const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.writeAll("Enter target (hexadecimal) : ");
        std.time.sleep(std.time.ns_per_hour);
        // const target_id = try ask_target();
    }
}

const salt: [16]u8 = .{ 112, 63, 240, 11, 151, 170, 17, 12, 168, 88, 154, 97, 28, 144, 121, 19 };

fn handle_auth(stream: std.net.Stream) !std.crypto.dh.X25519.KeyPair {
    const derived_seed = try ask_passphrase();

    const ed_key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(derived_seed);

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

fn ask_passphrase() ![32]u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.writeAll("Enter your passphrase : ");
        const seed = try stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 10000);
        defer std.heap.page_allocator.free(seed);

        if (seed.len < 35) {
            try stdout.writeAll("Too short passphrase\n");
            continue;
        }

        var space_count: usize = 0;

        for (seed) |c| {
            if (std.ascii.isWhitespace(c)) {
                space_count += 1;
            }
        }

        if (space_count > (seed.len / 3)) {
            try stdout.writeAll("Too many whitespaces\n");
            continue;
        }

        var derived_seed: [32]u8 = undefined;
        try std.crypto.pwhash.argon2.kdf(std.heap.page_allocator, &derived_seed, seed, &salt, .owasp_2id, .argon2id);

        return derived_seed;
    }
}
