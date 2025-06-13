const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;
const api = @import("client/api.zig");
const abstraction = @import("client/abstraction.zig");
const Queue = @import("client/queue.zig").Queue;
const queues = @import("client/queues.zig");

fn handle_incoming_data(reader: std.io.AnyReader, allocator: std.mem.Allocator) !void {
    const target = try reader.readByte();
    const len = try reader.readInt(u64, .big);
    const data = try allocator.alloc(u8, len);
    try reader.readNoEof(data);

    switch (target) {
        0 => try queues.read_messages_receive_queue.append(data),
        1 => try queues.send_actions_receive_queue.append(data),
        else => return error.InvalidPaquetTarget,
    }
}

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    queues.read_messages_receive_queue = Queue.init(std.heap.page_allocator);
    defer queues.read_messages_receive_queue.deinit();

    queues.send_actions_receive_queue = Queue.init(std.heap.page_allocator);
    defer queues.send_actions_receive_queue.deinit();

    const stream = blk: {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        const is_gui = if (std.mem.eql(u8, args[1], "gui")) true else if (std.mem.eql(u8, args[1], "cli")) false else std.debug.panic("Invalid argument `{s}`", .{args[1]});
        abstraction.init(is_gui);

        break :blk try abstraction.connect_to_server(args[2..]);
    };
    defer abstraction.deinit();
    defer stream.close();

    const x25519_key_pair = try abstraction.handle_auth(stream);

    const pubkey = x25519_key_pair.public_key;

    {
        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    const writer = stream.writer();
    const reader = stream.reader();

    _ = try std.Thread.spawn(.{}, handle_incoming_data, .{ reader.any(), allocator });

    _ = try std.Thread.spawn(.{}, listen_for_messages, .{ x25519_key_pair.secret_key, x25519_key_pair.public_key });

    while (true) {
        const target_id = try abstraction.ask_target_id(pubkey);
        const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target_id);

        const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

        while (true) {
            const raw_message = abstraction.ask_message(pubkey, target_id) catch |err| {
                if (err == error.DMExit) break;
                return err;
            };
            defer allocator.free(raw_message);

            //Encrypt message
            //TODO probably vulnerable to attacks
            //TODO perhaps add variable-sized data before/after the message and specify where it is in the encrypted part of the message
            encrypt_decrypt_message(raw_message, symmetric_key);

            api.send_message(writer.any(), target_id, raw_message) catch |err| {
                std.log.err("Error while sending message : {}", .{err});
                continue;
            };
        }
    }
}

fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

fn listen_for_messages(my_privkey: [32]u8, pubkey: [32]u8) !void {
    const allocator = std.heap.page_allocator;

    while (true) {
        const full_message = try queues.read_messages_receive_queue.next();
        defer allocator.free(full_message);

        var author: [32]u8 = undefined;
        @memcpy(&author, full_message[0..32]);

        var i: usize = 32;

        var dm: ?[32]u8 = null;
        if (std.mem.eql(u8, &author, &pubkey)) {
            dm = undefined;
            @memcpy(&dm.?, full_message[32..64]);
            i = 64;
        }

        const author_pubkey = std.crypto.ecc.Curve25519.fromBytes(author);

        const symmetric_key = try get_symmetric_key(author_pubkey, my_privkey);

        const message = full_message[i..];

        //Decrypt
        encrypt_decrypt_message(message, symmetric_key);

        try abstraction.handle_new_message(author, dm, message);
    }
}

fn encrypt_decrypt_message(message: []u8, symmetric_key: [32]u8) void {
    for (message, 0..) |*c, i| {
        c.* ^= symmetric_key[i % symmetric_key.len];
    }
}
