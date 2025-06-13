const std = @import("std");
const salt = @import("../client.zig").salt;
const api = @import("api.zig");

pub fn ask_passphrase() ![32]u8 {
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

        return try @import("crypto.zig").derive(seed);
    }
}

/// Returned memory is owned by the caller
pub fn ask_message() ![]u8 {
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

pub fn ask_target_id() ![32]u8 {
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

pub fn handle_auth(stream: std.net.Stream) !std.crypto.dh.X25519.KeyPair {
    const derived_seed = try ask_passphrase();

    return try api.auth(stream, derived_seed);
}

pub fn connect_to_server(next_args: [][:0]u8) !std.net.Stream {
    if (next_args.len == 0) {
        const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

        return try std.net.tcpConnectToAddress(addr);
    } else {
        const port: u16 = if (next_args.len == 1) 8080 else try std.fmt.parseInt(u16, next_args[1], 10);

        return try std.net.tcpConnectToHost(std.heap.page_allocator, next_args[0], port);
    }
}

pub fn handle_new_message(author: [32]u8, dm: ?[32]u8, message: []const u8) void {
    //TODO perhaps use `dm`
    _ = dm;
    std.debug.print("{s}> {s}\n", .{ std.fmt.bytesToHex(author, .lower), message });
}
