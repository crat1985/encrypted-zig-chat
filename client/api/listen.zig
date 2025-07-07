const std = @import("std");
const Client = @import("../../client.zig");
const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;
const ReceivedFullEncryptedMessage = @import("../message/unencrypted.zig").ReceivedFullEncryptedMessage;
const SentFullEncryptedMessage = @import("../message/unencrypted.zig").SentFullEncryptedMessage;

const constants = @import("constants.zig");
const FULL_MESSAGE_SIZE = constants.FULL_MESSAGE_SIZE;
const ACTION_DATA_SIZE = constants.ACTION_DATA_SIZE;
const DECRYPTED_OUTPUT_DIR = constants.DECRYPTED_OUTPUT_DIR;
const PAYLOAD_AND_PADDING_SIZE = constants.PAYLOAD_AND_PADDING_SIZE;

const request = @import("request.zig");
const SendRequest = request.SendRequest;
const ReceiveRequest = request.ReceiveRequest;
const receive_requests = &request.receive_requests;
const GUI = @import("../gui.zig");
const socket = @import("socket.zig");

const allocator = std.heap.page_allocator;

const send_requests = &@import("request.zig").send_requests;

pub const ReceivedMessage = struct {
    from: [32]u8,
    to: [32]u8,
    msg_id: u64,
    action: EncryptedPart.Action,
};

pub fn read_messages(privkey: [32]u8, pubkey: [32]u8, reader: std.io.AnyReader) !void {
    while (true) {
        try handle_message(privkey, pubkey, reader);
    }
}

fn handle_message(privkey: [32]u8, pubkey: [32]u8, reader: std.io.AnyReader) !void {
    const decrypted_msg = try decrypt_message(&pubkey, privkey, reader);

    const dm_id = if (std.mem.eql(u8, &decrypted_msg.from, &pubkey)) decrypted_msg.to else decrypted_msg.from;

    const symmetric_key = try Client.get_symmetric_key(std.crypto.ecc.Curve25519.fromBytes(dm_id), privkey);

    switch (decrypted_msg.action) {
        .Decline => |_| {
            if (!send_requests.remove(decrypted_msg.msg_id)) {
                std.debug.panic("Trying to delete invalid send request id {d}\n", .{decrypted_msg.msg_id});
            }
        },
        .Accept => |_| {
            const entry = send_requests.fetchRemove(decrypted_msg.msg_id) orelse std.debug.panic("Invalid send request id {d}\n", .{decrypted_msg.msg_id});

            switch (entry.value.data) {
                .raw_message => |rm| std.debug.print("Accepted message request of size {d}o\n", .{rm.len}),
                .file => |f| std.debug.print("Accepted file send request `{s}` of size {d}o\n", .{ f.name[0..f.name_len], f.size }),
            }

            _ = try std.Thread.spawn(.{}, @import("data.zig").send_data, .{ entry.value, decrypted_msg.msg_id });
        },
        .SendFileRequest => |sfr| {
            //TODO ask the user if the message/file is huge (e.g. > 100ko) or if the message is from a new entity
            std.debug.print("New file request : `{s}` of size {d}o\n", .{ sfr.filename[0..sfr.filename_len], sfr.total_size });

            var padding: [ACTION_DATA_SIZE]u8 = undefined;
            std.crypto.random.bytes(&padding);

            const encrypted_part = EncryptedPart.init(decrypted_msg.msg_id, .{ .Accept = .{ ._padding = padding } });

            const full_msg = SentFullEncryptedMessage.encrypt(symmetric_key, decrypted_msg.from, encrypted_part);

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

            const rr = ReceiveRequest{
                .data = .{ .file = .{ .file = output_file, .filename = sfr.filename, .filename_len = sfr.filename_len } },
                .symmetric_key = symmetric_key,
                .target_id = decrypted_msg.from,
                .total_size = std.mem.readInt(u64, &sfr.total_size, .big),
            };

            {
                const entry = try receive_requests.getOrPut(decrypted_msg.msg_id);
                if (entry.found_existing) @panic("no");

                entry.value_ptr.* = rr;
            }

            {
                const lock = socket.lock_writer();
                defer lock.unlock();

                try lock.data.writeAll(std.mem.asBytes(&full_msg));
            }
        },
        .SendMessageRequest => |smr| {
            const total_size = std.mem.readInt(u64, &smr.total_size, .big);

            //TODO ask the user if the message/file is huge (e.g. > 100ko) or if the message is from a new entity
            std.debug.print("New message request of size {d}o\n", .{total_size});

            var padding: [ACTION_DATA_SIZE]u8 = undefined;
            std.crypto.random.bytes(&padding);

            const encrypted_part = EncryptedPart.init(decrypted_msg.msg_id, .{ .Accept = .{ ._padding = padding } });

            const full_msg = SentFullEncryptedMessage.encrypt(symmetric_key, decrypted_msg.from, encrypted_part);

            const out_message = try allocator.alloc(u8, total_size);

            const rr = ReceiveRequest{
                .data = .{ .raw_message = out_message },
                .symmetric_key = symmetric_key,
                .target_id = decrypted_msg.from,
                .total_size = total_size,
            };

            {
                const entry = try receive_requests.getOrPut(decrypted_msg.msg_id);
                if (entry.found_existing) @trap();

                entry.value_ptr.* = rr;
            }

            {
                const lock = socket.lock_writer();
                defer lock.unlock();

                try lock.data.writeAll(std.mem.asBytes(&full_msg));
            }
        },
        .SendData => |sd| {
            const index = std.mem.readInt(u32, &sd.index, .big);

            var is_file: bool = undefined;

            const total_size = blk: {
                const req = receive_requests.get(decrypted_msg.msg_id).?;
                switch (req.data) {
                    .file => is_file = true,
                    .raw_message => is_file = false,
                }

                break :blk req.total_size;
            };

            var payload_real_len: u64 = undefined;
            var is_last: bool = undefined;

            if (@as(u64, index + 1) * PAYLOAD_AND_PADDING_SIZE >= total_size) {
                payload_real_len = total_size % PAYLOAD_AND_PADDING_SIZE;
                is_last = true;
            } else {
                payload_real_len = PAYLOAD_AND_PADDING_SIZE;
                is_last = false;
            }

            const is_first = index == 0;

            std.debug.print("is_first = {}, is_last = {}, total_size = {d}, payload_real_len = {d}\n", .{ is_first, is_last, total_size, payload_real_len });

            if (!is_file) std.debug.print("Received data : {s}\n", .{sd.payload_and_padding[0..payload_real_len]});

            if (is_first and is_last) {
                {
                    if (!receive_requests.remove(decrypted_msg.msg_id)) {
                        std.debug.panic("Trying to delete invalid receive request id {d}\n", .{decrypted_msg.msg_id});
                    }
                }

                const content = try allocator.dupeZ(u8, sd.payload_and_padding[0..payload_real_len]);

                const msg = @import("../gui/messages.zig").Message{
                    .sent_by = if (std.mem.eql(u8, &pubkey, &decrypted_msg.from)) .Me else .NotMe,
                    .is_file = is_file,
                    .content = content,
                };

                try GUI.handle_new_message(msg, dm_id);

                return;
            }

            {
                const value =
                    if (is_last) receive_requests.fetchRemove(decrypted_msg.msg_id).?.value else receive_requests.get(decrypted_msg.msg_id).?;

                const content = sd.payload_and_padding[0..payload_real_len];

                {
                    const total_sent: f32 = @floatFromInt(@as(u64, index) * PAYLOAD_AND_PADDING_SIZE + content.len);
                    const avancement = total_sent / @as(f32, @floatFromInt(total_size)) * 100;

                    switch (value.data) {
                        .file => |f| {
                            std.debug.print("Received {d:.2}% of the file `{s}`\n", .{ avancement, f.filename[0..f.filename_len] });
                        },
                        .raw_message => {
                            std.debug.print("Received {d:.2}% of the message\n", .{avancement});
                        },
                    }
                }

                switch (value.data) {
                    .file => |f| {
                        try f.file.writeAll(content);

                        if (is_last) {
                            const contentz = try allocator.dupeZ(u8, f.filename[0..f.filename_len]);

                            const msg = @import("../gui/messages.zig").Message{
                                .sent_by = if (std.mem.eql(u8, &pubkey, &decrypted_msg.from)) .Me else .NotMe,
                                .is_file = is_file,
                                .content = contentz,
                            };

                            try GUI.handle_new_message(msg, dm_id);
                        }
                    },
                    .raw_message => |rm| {
                        @memcpy(rm[index .. index + content.len], content);

                        if (is_last) {
                            const contentz = try allocator.dupeZ(u8, rm);

                            const msg = @import("../gui/messages.zig").Message{
                                .sent_by = if (std.mem.eql(u8, &pubkey, &decrypted_msg.from)) .Me else .NotMe,
                                .is_file = is_file,
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

pub fn decrypt_message(pubkey: *const [32]u8, privkey: [32]u8, reader: std.io.AnyReader) !ReceivedMessage {
    const full_message: ReceivedFullEncryptedMessage = std.mem.bytesAsValue(ReceivedFullEncryptedMessage, &try reader.readBytesNoEof(FULL_MESSAGE_SIZE + 32)).*;

    const encryption_pubkey = if (std.mem.eql(u8, pubkey, &full_message.from)) full_message.data.target_id else full_message.from;

    const other_pubkey = std.crypto.ecc.Curve25519.fromBytes(encryption_pubkey);

    const symmetric_key = try @import("../../client.zig").get_symmetric_key(other_pubkey, privkey);

    var decrypted = try full_message.data.decrypt(symmetric_key);

    var decrypted_parsed: EncryptedPart = std.mem.bytesAsValue(EncryptedPart, &decrypted).*;

    const msg_id = std.mem.readInt(u64, &decrypted_parsed.msg_id, .big);

    switch (decrypted_parsed.action_kind) {
        .SendMessageRequest => {
            const encrypted_data: EncryptedPart.SendMessageRequest = std.mem.bytesAsValue(EncryptedPart.SendMessageRequest, &decrypted_parsed.data).*;

            const total_size = std.mem.readInt(u64, &encrypted_data.total_size, .big);

            std.debug.print("Send message request :\n- msg_id = {d}\n- Total size = {d}\n", .{ msg_id, total_size });

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .SendMessageRequest = .{ .total_size = encrypted_data.total_size, ._padding = encrypted_data._padding } },
            };
        },
        .SendData => {
            const encrypted_part: EncryptedPart.SendData = std.mem.bytesAsValue(EncryptedPart.SendData, &decrypted_parsed.data).*;

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .SendData = .{ .index = encrypted_part.index, .payload_and_padding = encrypted_part.payload_and_padding } },
            };
        },
        .SendFileRequest => {
            const encrypted_part: EncryptedPart.SendFileRequest = std.mem.bytesAsValue(EncryptedPart.SendFileRequest, &decrypted_parsed.data).*;

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .SendFileRequest = .{ .filename_len = encrypted_part.filename_len, .filename = encrypted_part.filename, .total_size = encrypted_part.total_size, ._padding = encrypted_part._padding } },
            };
        },
        .Accept => {
            const encrypted_part: EncryptedPart.AcceptOrDecline = std.mem.bytesAsValue(EncryptedPart.AcceptOrDecline, &decrypted_parsed.data).*;

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .Accept = .{ ._padding = encrypted_part._padding } },
            };
        },
        .Decline => {
            const encrypted_part: EncryptedPart.AcceptOrDecline = std.mem.bytesAsValue(EncryptedPart.AcceptOrDecline, &decrypted_parsed.data).*;

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .Decline = .{ ._padding = encrypted_part._padding } },
            };
        },
    }
}
