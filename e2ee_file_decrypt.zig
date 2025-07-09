const std = @import("std");

const allocator = std.heap.page_allocator;

///To make sure another program doesn't use the same dir name
const ENCRYPTED_CHAT_DIR_NAME = "zig_encrypted_chat_797898968";

const OUTPUT_FILE_DEFAULT_PREFIX = "decrypted_";

const utils = @import("client/api/utils.zig");
const constants = @import("client/api/constants.zig");

fn get_tmp_dir() ![]u8 {
    const prefix = switch (@import("builtin").target.os.tag) {
        .windows => std.process.getEnvVarOwned(allocator, "TEMP") catch try allocator.dupe(u8, "C:\\Windows\\Temp"),
        .macos, .linux => std.process.getEnvVarOwned(allocator, "TMPDIR") catch try allocator.dupe(u8, "/tmp"),
        else => @compileError("Unsupported OS"),
    };
    // defer allocator.free(prefix);

    // const tmp_dir = try std.fs.openDirAbsolute(prefix, .{});

    // //Create the app tmp directory
    // _ = try create_dir_if_does_not_exist(tmp_dir, ENCRYPTED_CHAT_DIR_NAME);

    // return try std.fs.path.join(allocator, &.{ prefix, ENCRYPTED_CHAT_DIR_NAME, &user_id });

    return prefix;
}

fn create_dir_if_does_not_exist(path: []const u8) !std.fs.Dir {
    std.fs.makeDirAbsolute(path) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    return try std.fs.openDirAbsolute(path, .{});
}

fn create_rel_dir_if_does_not_exist(dir: std.fs.Dir, file_name: []const u8) !std.fs.Dir {
    dir.makeDir(file_name) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    return try dir.openDir(file_name, .{});
}

pub fn main() !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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

    var user_id_hex: [64]u8 = undefined;

    const user_id: [32]u8 = while (true) {
        try stdout.writeAll("Enter the user ID : ");

        const user_id_hex_slice: []u8 = try stdin.readUntilDelimiterAlloc(allocator, '\n', 65);
        defer allocator.free(user_id_hex_slice);

        if (user_id_hex.len != 64) continue;

        @memcpy(&user_id_hex, user_id_hex_slice);

        var user_id: [32]u8 = undefined;

        _ = try std.fmt.hexToBytes(&user_id, &user_id_hex);

        break user_id;
    };

    const ed_key_pair = try std.crypto.sign.Ed25519.KeyPair.generateDeterministic(derived_passphrase);

    const keypair = try std.crypto.dh.X25519.KeyPair.fromEd25519(ed_key_pair);

    const symmetric_key = try @import("client.zig").get_symmetric_key(std.crypto.ecc.Curve25519.fromBytes(user_id), keypair.secret_key);

    const file_name = args[1];

    const APP_TMP_PATH = try get_tmp_dir();
    defer allocator.free(APP_TMP_PATH);

    var APP_TMP = try create_dir_if_does_not_exist(APP_TMP_PATH);
    defer APP_TMP.close();

    var out_dir = try create_rel_dir_if_does_not_exist(APP_TMP, &user_id_hex);
    defer out_dir.close();

    const outfile_name: []u8 =
        if (args.len == 2) blk: {
            const outfile_name = try std.fmt.allocPrint(allocator, OUTPUT_FILE_DEFAULT_PREFIX ++ "{s}", .{file_name});

            break :blk outfile_name;
        } else if (args.len == 3) try allocator.dupe(u8, args[2]) else {
            std.log.err("Too many arguments", .{});
            std.process.exit(0);
        };
    defer allocator.free(outfile_name);

    const full_path = try std.fs.path.join(allocator, &.{ APP_TMP_PATH, &user_id_hex, outfile_name });

    std.log.info("Creating output file {s}...", .{full_path});

    const outfile = try out_dir.createFile(outfile_name, .{});
    defer outfile.close();

    std.log.info("Created output file {s} successfully !", .{full_path});

    try decrypt_file(file_name, symmetric_key, outfile);

    std.log.info("Generated decrypted file {s} successfully !", .{full_path});
}

fn print_help(program_name: []const u8) void {
    std.debug.print("Usage : {s} input_file <output_file>\n", .{program_name});
}

const ENCRYPTED_BLOCK_SIZE = constants.PAYLOAD_AND_PADDING_SIZE + utils.CHACHA_DATA_LENGTH;

fn decrypt_file(name: []const u8, symmetric_key: [32]u8, out_file: std.fs.File) !void {
    const input_file = try std.fs.cwd().openFile(name, .{});
    const encrypted_file_size = (try input_file.metadata()).size();

    const reader = input_file.reader();

    const file_size_encrypted = try reader.readBytesNoEof(8 + utils.CHACHA_DATA_LENGTH);

    const decrypted_file_size_bytes = try utils.decrypt_chacha(8 + utils.CHACHA_DATA_LENGTH, &file_size_encrypted, symmetric_key);

    const decrypted_file_size = std.mem.readInt(u64, &decrypted_file_size_bytes, .big);

    const parts_count = @divExact(encrypted_file_size - (8 + utils.CHACHA_DATA_LENGTH), ENCRYPTED_BLOCK_SIZE);

    for (0..parts_count) |i| {
        const block = try reader.readBytesNoEof(ENCRYPTED_BLOCK_SIZE);
        const decrypted = try utils.decrypt_chacha(ENCRYPTED_BLOCK_SIZE, &block, symmetric_key);

        const end = if (i + 1 == parts_count) decrypted_file_size % ENCRYPTED_BLOCK_SIZE else decrypted.len;

        try out_file.writeAll(decrypted[0..end]);

        {
            const total_decrypted: f32 = @floatFromInt(i * ENCRYPTED_BLOCK_SIZE + end);
            const avancement = total_decrypted / @as(f32, @floatFromInt(decrypted_file_size)) * 100;
            std.debug.print("Decrypted {d:.2}% of the file\n", .{avancement});
        }
    }
}
