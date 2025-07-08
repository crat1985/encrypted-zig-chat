const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;
const constants = @import("client/api/constants.zig");
const FULL_MESSAGE_SIZE = constants.FULL_MESSAGE_SIZE;

const HashMapContext = @import("id_hashmap_ctx.zig").HashMapContext;

const HashMapType = std.HashMap([32]u8, []*Mutex(std.io.AnyWriter), HashMapContext, 70);

var users: HashMapType = undefined;

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub const DEFAULT_ADDR = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8080);

pub fn main() !void {
    users = HashMapType.init(std.heap.page_allocator);

    var server = try DEFAULT_ADDR.listen(.{
        .reuse_address = true,
        .reuse_port = true,
    });

    while (true) {
        const conn = try server.accept();
        std.log.info("New connection from {any}", .{conn.address});

        _ = try std.Thread.spawn(.{}, handle_conn, .{conn});
    }
}

fn handle_conn(conn: std.net.Server.Connection) !void {
    const stream = conn.stream;

    const reader = stream.reader().any();
    const _writer = stream.writer().any();

    const pubkey = try handle_auth(reader, _writer);

    var writer = Mutex(std.io.AnyWriter).init(_writer);

    const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);
    {
        std.log.info("{any} was authenticated as {s}", .{ conn.address, hex_pubkey });
    }

    const allocator = std.heap.page_allocator;

    try add_connection_to_users(pubkey, &writer);

    defer remove_connection_from_users(pubkey, &writer) catch unreachable;

    while (true) {
        const full_message = reader.readBytesNoEof(FULL_MESSAGE_SIZE) catch break; //EOF

        // var hasher = std.hash.Wyhash.init(0);
        // hasher.update(&full_message);
        // const hash = hasher.final();

        // std.debug.print("\n\nHash = {d}\n\n\n", .{hash});

        const target_id = full_message[0..32].*;

        // std.debug.print("UNECRYPTED DATA = {s}\n", .{std.fmt.bytesToHex(full_message[32 .. 32 + constants.FULL_MESSAGE_SIZE - constants.BLOCK_SIZE], .lower)});

        std.log.info("New message from {s} to {s}", .{ hex_pubkey, std.fmt.bytesToHex(target_id, .lower) });

        var target_conns: ?[]*Mutex(std.io.AnyWriter) = undefined;
        var my_conns: []*Mutex(std.io.AnyWriter) = undefined;

        {
            target_conns = if (std.mem.eql(u8, &target_id, &pubkey)) null else try allocator.dupe(*Mutex(std.io.AnyWriter), users.get(target_id) orelse {
                continue;
            });

            my_conns = try allocator.dupe(*Mutex(std.io.AnyWriter), users.get(pubkey) orelse {
                continue;
            });
        }
        defer if (target_conns) |conns| allocator.free(conns);
        defer allocator.free(my_conns);

        if (target_conns) |targets| {
            for (targets) |target_conn| {
                const lock = target_conn.lock();
                defer lock.unlock();

                try lock.data.writeAll(&pubkey);
                try lock.data.writeAll(&full_message);
            }
        }

        for (my_conns) |my_conn| {
            const lock = my_conn.lock();
            defer lock.unlock();

            try lock.data.writeAll(&pubkey);
            try lock.data.writeAll(&full_message);
        }
    }
}

fn handle_auth(reader: std.io.AnyReader, writer: std.io.AnyWriter) ![32]u8 {
    const raw_pubkey = try reader.readBytesNoEof(32);
    const pubkey = try std.crypto.sign.Ed25519.PublicKey.fromBytes(raw_pubkey);

    var challenge: [64]u8 = undefined;

    {
        std.crypto.random.bytes(&challenge);
        try writer.writeAll(&challenge);
    }

    const raw_signature = try reader.readBytesNoEof(64);
    const signature = std.crypto.sign.Ed25519.Signature.fromBytes(raw_signature);
    signature.verify(&challenge, pubkey) catch |err| {
        try writer.writeByte(1);
        return err;
    };

    try writer.writeByte(0); //send SUCCESS

    return try std.crypto.dh.X25519.publicKeyFromEd25519(pubkey);
}

fn add_connection_to_users(pubkey: [32]u8, conn: *Mutex(std.io.AnyWriter)) !void {
    const allocator = std.heap.page_allocator;

    const entry = try users.getOrPut(pubkey);
    if (entry.found_existing) {
        const new_slice = try allocator.alloc(*Mutex(std.io.AnyWriter), entry.value_ptr.len + 1);
        @memcpy(new_slice[0 .. new_slice.len - 1], entry.value_ptr.*);
        new_slice[new_slice.len - 1] = conn;
        allocator.free(entry.value_ptr.*);
        entry.value_ptr.* = new_slice;
    } else {
        const slice = try allocator.alloc(*Mutex(std.io.AnyWriter), 1);
        slice[0] = conn;
        entry.value_ptr.* = slice;
    }
}

fn remove_connection_from_users(pubkey: [32]u8, writer: *Mutex(std.io.AnyWriter)) !void {
    const allocator = std.heap.page_allocator;

    const get_entry = users.getEntry(pubkey) orelse @panic("This should not happen");
    const slice = get_entry.value_ptr.*;

    const i: usize = for (slice, 0..) |slice_conn, i| {
        if (slice_conn == writer) break i;
    } else @panic("Could not find connection to delete");

    const new_slice = allocator.alloc(*Mutex(std.io.AnyWriter), slice.len - 1) catch unreachable;
    @memcpy(new_slice[0..i], slice[0..i]);
    @memcpy(new_slice[i..], slice[i + 1 ..]); //TODO not sure this works if it is the last element

    allocator.free(slice);
    get_entry.value_ptr.* = new_slice;
}
