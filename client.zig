const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;
const api = @import("client/api.zig");
const message = @import("client/message.zig");
const GUI = @import("client/gui.zig");

fn handle_incoming_data(reader: std.io.AnyReader, privkey: [32]u8, pubkey: [32]u8) !void {
    while (true) {
        try handle_message(reader, privkey, pubkey);
    }
}

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub fn main() !void {
    GUI.init();
    defer GUI.deinit();

    const stream = try GUI.connect_to_server();
    defer stream.close();

    const x25519_key_pair = try GUI.handle_auth(stream);

    const pubkey = x25519_key_pair.public_key;

    {
        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    const writer = stream.writer();
    const reader = stream.reader();

    _ = try std.Thread.spawn(.{}, handle_incoming_data, .{ reader.any(), x25519_key_pair.secret_key, x25519_key_pair.public_key });

    while (true) {
        const target_id = try GUI.ask_target_id(pubkey);
        const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target_id);

        const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

        while (true) {
            const raw_message = GUI.ask_message(pubkey, target_id) catch |err| {
                if (err == error.DMExit) break;
                return err;
            };
            defer allocator.free(raw_message);

            try message.encrypt_message_and_send(writer.any(), symmetric_key, target_id, raw_message);
        }
    }
}

pub fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

const allocator = std.heap.page_allocator;

fn handle_message(reader: std.io.AnyReader, privkey: [32]u8, pubkey: [32]u8) !void {
    const block_count = try reader.readInt(u32, .big);

    const author = try reader.readBytesNoEof(32);

    var dm: ?[32]u8 = null;
    if (std.mem.eql(u8, &author, &pubkey)) {
        dm = try reader.readBytesNoEof(32);
    }

    const author_pubkey = std.crypto.ecc.Curve25519.fromBytes(if (dm) |dm_unwrap| dm_unwrap else author);

    const decrypted_msg = try message.decrypt_message(block_count, privkey, author_pubkey, reader);
    defer allocator.free(decrypted_msg);

    try GUI.handle_new_message(author, dm, decrypted_msg);
}
