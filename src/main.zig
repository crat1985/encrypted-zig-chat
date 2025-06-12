const std = @import("std");

pub fn main() !void {
    const addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, 8080);

    var server = try addr.listen(.{});

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
}

fn handle_auth(reader: std.io.AnyReader, writer: std.io.AnyWriter) ![32]u8 {
    const raw_pubkey = try reader.readBytesNoEof(32); //LITTLE ENDIAN
    const pubkey = try std.crypto.sign.Ed25519.PublicKey.fromBytes(raw_pubkey);

    var challenge: [64]u8 = undefined;

    {
        std.crypto.random.bytes(&challenge);
        try writer.writeAll(&challenge);
    }

    const raw_signature = try reader.readBytesNoEof(64); //LITTLE ENDIAN
    const signature = std.crypto.sign.Ed25519.Signature.fromBytes(raw_signature);
    try signature.verify(&challenge, pubkey);

    try writer.writeByte(0); //send SUCCESS

    return try std.crypto.dh.X25519.publicKeyFromEd25519(pubkey);
}
