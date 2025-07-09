const std = @import("std");

const allocator = std.heap.page_allocator;

const OUTPUT_FILE_DEFAULT_PREFIX = "decrypted_";

const utils = @import("client/api/utils.zig");
const constants = @import("client/api/constants.zig");

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    const program_name = args[0];

    if (args.len == 1) {
        print_help(program_name);
        return;
    }

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("Enter your passphrase : ");

    const derived_passphrase = blk: {
        const passphrase: []u8 = try stdin.readUntilDelimiterAlloc(allocator, '\n', 10000);
        defer allocator.free(passphrase);

        break :blk try @import("client/crypto.zig").derive(passphrase);
    };

    const user_id: [32]u8 = while (true) {
        try stdout.writeAll("Enter the user ID : ");

        const user_id_hex: []u8 = try stdin.readUntilDelimiterAlloc(allocator, '\n', 65);
        defer allocator.free(user_id_hex);

        if (user_id_hex.len != 64) continue;

        var user_id: [32]u8 = undefined;

        _ = try std.fmt.hexToBytes(&user_id, user_id_hex);

        break user_id;
    };

    const ed_key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(derived_passphrase);

    const keypair = try std.crypto.dh.X25519.KeyPair.fromEd25519(ed_key_pair);

    const symmetric_key = try @import("client.zig").get_symmetric_key(std.crypto.ecc.Curve25519.fromBytes(user_id), keypair.secret_key);

    const file_name = args[1];

    if (args.len == 2) {
        const outfile = try std.fmt.allocPrint(allocator, OUTPUT_FILE_DEFAULT_PREFIX ++ "{s}", .{file_name});
        defer allocator.free(outfile);

        try decrypt_file(file_name, symmetric_key, outfile);
        return;
    }

    const out_file = args[2];

    if (args.len == 3) {
        try decrypt_file(file_name, symmetric_key, out_file);
        return;
    }

    std.debug.print("Too many arguments\n", .{});
}

fn print_help(program_name: []const u8) void {
    std.debug.print("Usage : {s} input_file <output_file>\n", .{program_name});
}

const ENCRYPTED_BLOCK_SIZE = constants.PAYLOAD_AND_PADDING_SIZE + utils.CHACHA_DATA_LENGTH;

fn decrypt_file(name: []const u8, symmetric_key: [32]u8, out_file: []const u8) !void {
    const input_file = try std.fs.cwd().openFile(name, .{});
    const encrypted_file_size = (try input_file.metadata()).size();

    const reader = input_file.reader();

    const output_file = try std.fs.cwd().createFile(out_file, .{});
    const writer = output_file.writer();

    const file_size_encrypted = try reader.readBytesNoEof(8 + utils.CHACHA_DATA_LENGTH);

    const decrypted_file_size_bytes = try utils.decrypt_chacha(8 + utils.CHACHA_DATA_LENGTH, &file_size_encrypted, symmetric_key);

    const decrypted_file_size = std.mem.readInt(u64, &decrypted_file_size_bytes, .big);

    const parts_count = @divExact(encrypted_file_size - (8 + utils.CHACHA_DATA_LENGTH), ENCRYPTED_BLOCK_SIZE);

    for (0..parts_count) |i| {
        const block = try reader.readBytesNoEof(ENCRYPTED_BLOCK_SIZE);
        const decrypted = try utils.decrypt_chacha(ENCRYPTED_BLOCK_SIZE, &block, symmetric_key);

        if (i + 1 == parts_count) {
            const end = decrypted_file_size % ENCRYPTED_BLOCK_SIZE;
            try writer.writeAll(decrypted[0..end]);
        } else {
            try writer.writeAll(&decrypted);
        }
    }
}
