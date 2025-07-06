const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;
const message_mod = @import("client/message.zig");

const HashMapContext = @import("id_hashmap_ctx.zig").HashMapContext;

const HashMapType = std.HashMap([32]u8, []std.net.Server.Connection, HashMapContext, 70);

var users: HashMapType = undefined;

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub fn main() !void {
    users = HashMapType.init(std.heap.page_allocator);

    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8080);

    var server = try addr.listen(.{
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
    const writer = stream.writer().any();

    const pubkey = try handle_auth(reader, writer);

    const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);
    {
        std.log.info("{any} was authenticated as {s}", .{ conn.address, hex_pubkey });
    }

    const allocator = std.heap.page_allocator;

    try add_connection_to_users(pubkey, conn);

    defer remove_connection_from_users(pubkey, conn.stream) catch unreachable;

    while (true) {
        const full_message = reader.readBytesNoEof(message_mod.FULL_MESSAGE_SIZE) catch break; //EOF

        const target_id = full_message[0..32].*;

        std.log.info("New message from {s} to {s}", .{ hex_pubkey, std.fmt.bytesToHex(target_id, .lower) });

        var target_conns: ?[]std.net.Server.Connection = undefined;
        var my_conns: []std.net.Server.Connection = undefined;

        {
            const users_lock = &users;

            target_conns = if (std.mem.eql(u8, &target_id, &pubkey)) null else try allocator.dupe(std.net.Server.Connection, users_lock.get(target_id) orelse {
                continue;
            });

            my_conns = try allocator.dupe(std.net.Server.Connection, users_lock.get(pubkey) orelse {
                continue;
            });
        }
        defer if (target_conns) |conns| allocator.free(conns);
        defer allocator.free(my_conns);

        if (target_conns) |targets| {
            for (targets) |target_conn| {
                const target_writer = target_conn.stream.writer();

                try target_writer.writeAll(&pubkey);
                try target_writer.writeAll(&full_message);
            }
        }

        for (my_conns) |my_conn| {
            const target_me_writer = my_conn.stream.writer();

            try target_me_writer.writeAll(&pubkey);
            try target_me_writer.writeAll(&full_message);
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

fn add_connection_to_users(pubkey: [32]u8, conn: std.net.Server.Connection) !void {
    const allocator = std.heap.page_allocator;

    const users_lock = &users;

    const entry = try users_lock.getOrPut(pubkey);
    if (entry.found_existing) {
        const new_slice = try allocator.alloc(std.net.Server.Connection, entry.value_ptr.len + 1);
        @memcpy(new_slice[0 .. new_slice.len - 1], entry.value_ptr.*);
        new_slice[new_slice.len - 1] = conn;
        allocator.free(entry.value_ptr.*);
        entry.value_ptr.* = new_slice;
    } else {
        const slice = try allocator.alloc(std.net.Server.Connection, 1);
        slice[0] = conn;
        entry.value_ptr.* = slice;
    }
}

fn remove_connection_from_users(pubkey: [32]u8, stream: std.net.Stream) !void {
    const allocator = std.heap.page_allocator;

    const users_lock = &users;

    const get_entry = users_lock.getEntry(pubkey) orelse @panic("This should not happen");
    const slice = get_entry.value_ptr.*;

    const i: usize = for (slice, 0..) |slice_conn, i| {
        if (slice_conn.stream.handle == stream.handle) break i;
    } else @panic("Could not find connection to delete");

    const new_slice = allocator.alloc(std.net.Server.Connection, slice.len - 1) catch unreachable;
    @memcpy(new_slice[0..i], slice[0..i]);
    @memcpy(new_slice[i..], slice[i + 1 ..]); //TODO not sure this works if it is the last element

    allocator.free(slice);
    get_entry.value_ptr.* = new_slice;
}
