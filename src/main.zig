const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;

const HashMapContext = struct {
    const Self = @This();

    pub fn hash(_: Self, key: [32]u8) u64 {
        const Hasher = std.hash.Wyhash;

        var hasher = Hasher.init(0);
        hasher.update(&key);
        return hasher.final();
    }

    pub fn eql(_: Self, k1: [32]u8, k2: [32]u8) bool {
        return std.mem.eql(u8, &k1, &k2);
    }
};

const HashMapType = std.HashMap([32]u8, []std.net.Server.Connection, HashMapContext, 70);

var users: Mutex(HashMapType) = undefined;

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub fn main() !void {
    users = Mutex(HashMapType).init(HashMapType.init(std.heap.page_allocator));

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

    {
        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("{any} was authenticated as {s}", .{ conn.address, hex_pubkey });
    }

    const allocator = std.heap.page_allocator;

    try add_connection_to_users(pubkey, conn);

    defer remove_connection_from_users(pubkey, conn.stream) catch unreachable;

    while (true) {
        const target_id = reader.readBytesNoEof(32) catch break; //EOF
        const users_lock = users.lock();
        const target_conns = users_lock.get(target_id) orelse {
            try send_packet(.Other, &.{1}, writer);
            continue;
        };
        users.unlock();
        try send_packet(.Other, &.{0}, writer);

        const message_size = try reader.readInt(u64, .big);
        const message = try allocator.alloc(u8, message_size);
        defer allocator.free(message);
        try reader.readNoEof(message);

        std.log.info("New message of size {d} from user {s} : {s}", .{ message_size, std.fmt.bytesToHex(target_id, .lower), message });

        const full_packet = try allocator.alloc(u8, pubkey.len + message.len);
        defer allocator.free(full_packet);
        @memcpy(full_packet[0..32], &pubkey);
        @memcpy(full_packet[32..], message);

        for (target_conns) |target_conn| {
            const target_writer = target_conn.stream.writer().any();

            try send_packet(.NewMessagesListener, full_packet, target_writer);
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
    try signature.verify(&challenge, pubkey);

    try writer.writeByte(0); //send SUCCESS

    return try std.crypto.dh.X25519.publicKeyFromEd25519(pubkey);
}

fn add_connection_to_users(pubkey: [32]u8, conn: std.net.Server.Connection) !void {
    const allocator = std.heap.page_allocator;

    const users_lock = users.lock();
    defer users.unlock();

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

    const users_lock = users.lock();
    defer users.unlock();

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

const PacketTarget = enum(u8) {
    NewMessagesListener = 0,
    Other = 1,
};

///must be already encrypted
fn send_packet(to: PacketTarget, data: []const u8, writer: std.io.AnyWriter) !void {
    try writer.writeByte(@intFromEnum(to));
    try writer.writeInt(u64, data.len, .big);
    try writer.writeAll(data);
}
