const std = @import("std");
const api = @import("client/api.zig");
const message = @import("client/message.zig");
const GUI = @import("client/gui.zig");
const C = @import("client/gui/c.zig").C;
const mutex = @import("mutex.zig");
const Mutex = mutex.Mutex;

fn handle_incoming_data(reader: std.io.AnyReader, writer: *Mutex(std.io.AnyWriter), privkey: [32]u8, pubkey: [32]u8) !void {
    while (true) {
        try handle_message(reader, writer, privkey, pubkey);
    }
}

pub const std_options: std.Options = .{
    // Set the log level to info
    .log_level = .info,
};

pub const DMState = union(enum) {
    Manual: struct {
        manual_target_id: [64:0]u8 = std.mem.zeroes([64:0]u8),
        manual_target_id_index: usize = 0,
    },
    NotManual: void,
};

pub fn main() !void {
    GUI.init();
    defer GUI.deinit();

    message.send_requests = std.AutoHashMap(u64, message.SendRequest).init(allocator);
    defer message.send_requests.deinit();

    const stream = try GUI.connect_to_server();
    defer stream.close();

    const x25519_key_pair = try GUI.handle_auth(stream);

    const pubkey = x25519_key_pair.public_key;

    {
        const hex_pubkey = std.fmt.bytesToHex(pubkey, .lower);

        std.log.info("You were authenticated as {s}", .{hex_pubkey});
    }

    var writer = Mutex(std.io.AnyWriter).init(stream.writer().any());
    const reader = stream.reader();

    _ = try std.Thread.spawn(.{}, handle_incoming_data, .{ reader.any(), &writer, x25519_key_pair.secret_key, x25519_key_pair.public_key });

    var target_id: ?[32]u8 = null;

    var cursor = C.MOUSE_CURSOR_DEFAULT;

    var dm_state: DMState = .{ .NotManual = {} };

    var current_message: [:0]c_int = try allocator.allocSentinel(c_int, 0, 0);
    defer allocator.free(current_message);

    while (!C.WindowShouldClose()) {
        cursor = C.MOUSE_CURSOR_DEFAULT;

        C.BeginDrawing();
        defer C.EndDrawing();

        defer C.SetMouseCursor(cursor);

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = C.GetScreenWidth();
        GUI.HEIGHT = C.GetScreenHeight();

        const sidebar_rect = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(if (target_id) |_| @divTrunc(GUI.WIDTH, 4) else GUI.WIDTH),
            .height = @floatFromInt(GUI.HEIGHT),
        };

        try GUI.draw_choose_discussion_sidebar(pubkey, &target_id, &cursor, sidebar_rect, &dm_state);

        if (target_id) |target| {
            const target_id_parsed = std.crypto.dh.X25519.Curve.fromBytes(target);

            const symmetric_key = try get_symmetric_key(target_id_parsed, x25519_key_pair.secret_key);

            const bounds = C.Rectangle{
                .x = sidebar_rect.width,
                .y = 0,
                .width = @as(f32, @floatFromInt(GUI.WIDTH)) - sidebar_rect.width,
                .height = @floatFromInt(GUI.HEIGHT),
            };

            const message_keyboard_enabled = switch (dm_state) {
                .NotManual => true,
                .Manual => false,
            };

            try GUI.draw_dm_screen(pubkey, target, &current_message, bounds, message_keyboard_enabled, &cursor, &writer, symmetric_key, &target_id);

            C.DrawLineV(.{ .x = sidebar_rect.x + sidebar_rect.width, .y = sidebar_rect.y }, .{ .x = sidebar_rect.x + sidebar_rect.width, .y = sidebar_rect.y + sidebar_rect.height }, C.WHITE);

            if (C.IsFileDropped()) {
                const files = C.LoadDroppedFiles();
                defer C.UnloadDroppedFiles(files);

                const files_slice = files.paths[0..@intCast(files.count)];

                for (files_slice) |file_path| {
                    const file_name = C.GetFileName(file_path);
                    const file_name_n: usize = @intCast(C.TextLength(file_name));
                    var file_name_array: [255]u8 = undefined;
                    @memcpy(file_name_array[0..file_name_n], file_name[0..file_name_n]);

                    try message.send_request(&writer, symmetric_key, target, .{ .file = .{ .file = try std.fs.openFileAbsolute(file_name_array[0..file_name_n], .{}), .name = file_name_array, .name_len = @intCast(file_name_n) } });
                }
            }
        }
    }
}

pub fn get_symmetric_key(public_key: std.crypto.ecc.Curve25519, priv_key: [32]u8) ![32]u8 {
    return (try public_key.clampedMul(priv_key)).toBytes();
}

const allocator = std.heap.page_allocator;

const DECRYPTED_OUTPUT_DIR = "decrypted_files";

fn handle_message(reader: std.io.AnyReader, writer: *Mutex(std.io.AnyWriter), privkey: [32]u8, pubkey: [32]u8) !void {
    const decrypted_msg = try message.decrypt_message(&pubkey, privkey, reader);

    const dm_id = if (std.mem.eql(u8, &decrypted_msg.from, &pubkey)) decrypted_msg.to else decrypted_msg.from;

    const symmetric_key = try get_symmetric_key(std.crypto.ecc.Curve25519.fromBytes(dm_id), privkey);

    switch (decrypted_msg.action) {
        .Decline => |_| {
            const reqs = &message.send_requests;

            if (!reqs.remove(decrypted_msg.msg_id)) {
                std.debug.panic("Trying to delete invalid send request id {d}\n", .{decrypted_msg.msg_id});
            }
        },
        .Accept => |_| {
            const reqs = &message.send_requests;

            const entry = reqs.fetchRemove(decrypted_msg.msg_id) orelse std.debug.panic("Invalid send request id {d}\n", .{decrypted_msg.msg_id});

            try entry.value.make(writer, decrypted_msg.msg_id);
        },
        .SendFileRequest => |sfr| {
            //TODO ask the user if the message/file is huge (e.g. > 100ko) or if the message is from a new entity
            std.debug.print("New file request : `{s}` of size {d}o\n", .{ sfr.filename[0..sfr.filename_len], sfr.total_size });

            var padding: [message.ACTION_DATA_SIZE]u8 = undefined;
            std.crypto.random.bytes(&padding);

            const encrypted_part = message.EncryptedPart.init(decrypted_msg.msg_id, .{ .Accept = .{ ._padding = padding } });

            const full_msg = message.SentFullEncryptedMessage.encrypt(symmetric_key, decrypted_msg.from, encrypted_part).encode();

            const output_file = blk: {
                const cwd = std.fs.cwd();
                cwd.makeDir(DECRYPTED_OUTPUT_DIR) catch |err| {
                    switch (err) {
                        error.PathAlreadyExists => {},
                        else => return err,
                    }
                };

                var dir = try cwd.openDir(DECRYPTED_OUTPUT_DIR, .{});
                defer dir.close();

                const file = try dir.createFile(sfr.filename[0..sfr.filename_len], .{});

                break :blk file;
            };

            const rr = message.ReceiveRequest{
                .data = .{ .file = output_file },
                .symmetric_key = symmetric_key,
                .target_id = decrypted_msg.from,
                .total_size = std.mem.readInt(u64, &sfr.total_size, .big),
            };

            {
                const lock = &message.receive_requests;

                const entry = try lock.getOrPut(decrypted_msg.msg_id);
                if (entry.found_existing) @panic("no");

                entry.value_ptr.* = rr;
            }

            {
                const lock = writer.lock();
                defer writer.unlock();

                try lock.writeAll(&full_msg);
            }
        },
        .SendMessageRequest => |smr| {
            const total_size = std.mem.readInt(u64, &smr.total_size, .big);

            //TODO ask the user if the message/file is huge (e.g. > 100ko) or if the message is from a new entity
            std.debug.print("New message request of size {d}o\n", .{total_size});

            var padding: [message.ACTION_DATA_SIZE]u8 = undefined;
            std.crypto.random.bytes(&padding);

            const encrypted_part = message.EncryptedPart.init(decrypted_msg.msg_id, .{ .Accept = .{ ._padding = padding } });

            const full_msg = message.SentFullEncryptedMessage.encrypt(symmetric_key, decrypted_msg.from, encrypted_part).encode();

            const out_message = try allocator.alloc(u8, total_size);

            const rr = message.ReceiveRequest{
                .data = .{ .raw_message = out_message },
                .symmetric_key = symmetric_key,
                .target_id = decrypted_msg.from,
                .total_size = total_size,
            };

            std.debug.print("lock count = {d}, unlock count = {d}\n", .{ mutex.lock_count, mutex.unlock_count });

            {
                const lock = &message.receive_requests;

                const entry = try lock.getOrPut(decrypted_msg.msg_id);
                if (entry.found_existing) @panic("no");

                entry.value_ptr.* = rr;
            }

            {
                const lock = writer.lock();
                defer writer.unlock();

                try lock.writeAll(&full_msg);
            }
        },
        .SendData => |sd| {
            const index = std.mem.readInt(u32, &sd.index, .big);

            const total_size = blk: {
                const reqs = &message.receive_requests;
                break :blk reqs.get(decrypted_msg.msg_id).?.total_size;
            };

            const is_last = index * message.PAYLOAD_AND_PADDING_SIZE + decrypted_msg.payload_real_len == total_size;

            const is_first = index == 0;

            if (is_first and is_last) {
                {
                    const reqs = &message.receive_requests;

                    if (!reqs.remove(decrypted_msg.msg_id)) {
                        std.debug.panic("Trying to delete invalid receive request id {d}\n", .{decrypted_msg.msg_id});
                    }
                }

                const content = try allocator.dupeZ(u8, sd.payload_and_padding[0..decrypted_msg.payload_real_len]);

                const msg = @import("client/gui/messages.zig").Message{
                    .sent_by = if (std.mem.eql(u8, &pubkey, &decrypted_msg.from)) .Me else .NotMe,
                    .content = content,
                };

                try GUI.handle_new_message(msg, dm_id);

                return;
            }

            {
                const value = blk: {
                    const lock = &message.receive_requests;

                    break :blk if (is_last) lock.fetchRemove(decrypted_msg.msg_id).?.value else lock.get(decrypted_msg.msg_id).?;
                };

                const content = sd.payload_and_padding[0..decrypted_msg.payload_real_len];

                switch (value.data) {
                    .file => |f| {
                        try f.writeAll(content);
                    },
                    .raw_message => |rm| {
                        @memcpy(rm[index .. index + content.len], content);

                        if (is_last) {
                            const contentz = try allocator.dupeZ(u8, rm);

                            const msg = @import("client/gui/messages.zig").Message{
                                .sent_by = if (std.mem.eql(u8, &pubkey, &decrypted_msg.from)) .Me else .NotMe,
                                .content = contentz,
                            };

                            try GUI.handle_new_message(msg, dm_id);
                        }
                    },
                }
            }
        },
    }
}
