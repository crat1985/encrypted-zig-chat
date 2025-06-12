const std = @import("std");
const Mutex = @import("src/mutex.zig").Mutex;

pub const Queue = struct {
    data: Mutex([][]u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const data = allocator.alloc([]u8, 0) catch unreachable;

        return .{
            .data = Mutex([][]u8).init(data),
            .allocator = allocator,
        };
    }

    pub fn append(self: *Self, data: []u8) !void {
        const lock = self.data.lock();
        defer self.data.unlock();

        const new_slice = try self.allocator.alloc([]u8, lock.len + 1);
        @memcpy(new_slice[0 .. new_slice.len - 1], lock.*);
        new_slice[new_slice.len - 1] = data;
        self.allocator.free(lock.*);

        lock.* = new_slice;
    }

    pub fn next(self: *Self) ![]u8 {
        const data_lock = while (true) {
            const lock = self.data.lock();

            if (lock.len != 0) break lock;

            self.data.unlock();

            std.time.sleep(std.time.ns_per_ms * 6);
        }; //wait for data to be added

        const data = data_lock.*[0];

        const new_slice = try self.allocator.alloc([]u8, data_lock.len - 1);
        @memcpy(new_slice, data_lock.*[1..]);
        self.allocator.free(data_lock.*);

        data_lock.* = new_slice;

        return data;
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data._data);
    }
};

///0
var read_messages_receive_queue: Queue = undefined;
///1
var send_actions_receive_queue: Queue = undefined;

fn handle_incoming_data(reader: std.io.AnyReader, allocator: std.mem.Allocator) !void {
    const target = try reader.readByte();
    const len = try reader.readInt(u64, .big);
    const data = try allocator.alloc(u8, len);
    try reader.readNoEof(data);

    switch (target) {
        0 => try read_messages_receive_queue.append(data),
        1 => try send_actions_receive_queue.append(data),
        else => return error.InvalidPaquetTarget,
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    read_messages_receive_queue = Queue.init(std.heap.page_allocator);
    defer read_messages_receive_queue.deinit();

    send_actions_receive_queue = Queue.init(std.heap.page_allocator);
    defer send_actions_receive_queue.deinit();

    const args = try std.process.argsAlloc(allocator);

    const stream = if (args.len == 1) blk: {
        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

        break :blk try std.net.tcpConnectToAddress(addr);
    } else blk: {
        const port: u16 = if (args.len == 2) 8080 else try std.fmt.parseInt(u16, args[2], 10);
        break :blk try std.net.tcpConnectToHost(allocator, args[1], port);
    };
    defer stream.close();

    const x25519_key_pair = try handle_auth(stream);

    {
        const pubkey = x25519_key_pair.public_key;

        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    const writer = stream.writer();
    const reader = stream.reader();

    _ = try std.Thread.spawn(.{}, handle_incoming_data, .{ reader.any(), std.heap.page_allocator });

    _ = try std.Thread.spawn(.{}, listen_for_messages, .{x25519_key_pair.secret_key});

    while (true) {
        const target_id = try ask_target_id();
        const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target_id);

        const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

        while (true) {
            const raw_message = ask_message() catch |err| {
                if (err == error.DMExit) break;
                return err;
            };
            defer allocator.free(raw_message);

            //Encrypt message
            //TODO probably vulnerable to attacks
            //TODO perhaps add variable-sized data before/after the message and specify where it is in the encrypted part of the message
            for (raw_message, 0..) |*c, i| {
                c.* ^= symmetric_key[i % symmetric_key.len];
            }

            try writer.writeAll(&target_id);

            {
                const res = try send_actions_receive_queue.next();
                if (!std.mem.eql(u8, res, &.{0})) {
                    std.debug.print("Unable to find user\n", .{});
                    continue;
                }
            }

            try writer.writeInt(u64, raw_message.len, .big);
            try writer.writeAll(raw_message);
        }
    }
}

fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

/// Returned memory is owned by the caller
fn ask_message() ![]u8 {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    while (true) {
        try stdout.writeAll("Enter message (:q to quit, \\:q to escape it if alone) : ");
        const message = try stdin.readUntilDelimiterAlloc(std.heap.page_allocator, '\n', 10000);

        //TODO trim the message
        if (message.len == 0) {
            std.debug.print("Please enter a non-empty message", .{});
            continue;
        }

        if (std.mem.eql(u8, message, ":q")) {
            return error.DMExit;
        }

        if (std.mem.eql(u8, message, "\\:q")) {
            std.heap.page_allocator.free(message);
            return std.heap.page_allocator.dupe(u8, ":q");
        }

        return message;
    }
}

fn listen_for_messages(my_privkey: [32]u8) !void {
    const allocator = std.heap.page_allocator;

    while (true) {
        const full_message = try read_messages_receive_queue.next();
        defer allocator.free(full_message);

        var author: [32]u8 = undefined;
        @memcpy(&author, full_message[0..32]);

        const author_pubkey = std.crypto.ecc.Curve25519.fromBytes(author);

        const symmetric_key = try get_symmetric_key(author_pubkey, my_privkey);

        const message = full_message[32..];

        //Decrypt
        for (message, 0..) |*c, i| {
            c.* ^= symmetric_key[i % symmetric_key.len];
        }

        std.debug.print("{s}> {s}\n", .{ std.fmt.bytesToHex(author, .lower), message });
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

fn ask_target_id() ![32]u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    while (true) {
        try stdout.writeAll("Enter target (hexadecimal) (enter :q to exit) : ");
        var hex_id: [64]u8 = undefined;
        const n = try stdin.read(&hex_id);
        if (n < 2) {
            std.debug.print("Invalid ID\n", .{});
            continue;
        }
        if (std.mem.eql(u8, hex_id[0..2], ":q")) {
            std.debug.print("See you soon !\n", .{});
            std.process.exit(0); //TODO handle that better (for e.g. close the connection)
        }
        if (n != hex_id.len) {
            std.debug.print("Invalid ID\n", .{});
            continue;
        }

        _ = try stdin.readByte(); //skip the new line character

        var raw_id: [32]u8 = undefined;

        _ = try std.fmt.hexToBytes(&raw_id, &hex_id);

        return raw_id;
    }
}
