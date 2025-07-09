const std = @import("std");
const Client = @import("../../client.zig");
const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;
const ReceivedFullEncryptedMessage = @import("../message/unencrypted.zig").ReceivedFullEncryptedMessage;
const SentFullEncryptedMessage = @import("../message/unencrypted.zig").SentFullEncryptedMessage;
const send = @import("send.zig");
const utils = @import("utils.zig");

const constants = @import("constants.zig");
const FULL_MESSAGE_SIZE = constants.FULL_MESSAGE_SIZE;
const ACTION_DATA_SIZE = constants.ACTION_DATA_SIZE;
const DECRYPTED_OUTPUT_DIR = constants.DECRYPTED_OUTPUT_DIR;
const PAYLOAD_AND_PADDING_SIZE = constants.PAYLOAD_AND_PADDING_SIZE;

const request = @import("request.zig");
const SendRequest = request.SendRequest;
const ReceiveRequest = request.ReceiveRequest;
const receive_requests = &request.receive_requests;
const unvalidated_receive_requests = &request.unvalidated_receive_requests;
const GUI = @import("../gui.zig");
const socket = @import("socket.zig");

const allocator = std.heap.page_allocator;

const send_requests = &@import("request.zig").send_requests;

pub fn read_messages(privkey: [32]u8, pubkey: [32]u8, reader: std.io.AnyReader) !void {
    while (true) {
        try handle_message(privkey, pubkey, reader);
    }
}

fn handle_message(privkey: [32]u8, pubkey: [32]u8, reader: std.io.AnyReader) !void {
    const full_message_bytes = try reader.readBytesNoEof(FULL_MESSAGE_SIZE + 32);

    const full_message: ReceivedFullEncryptedMessage = std.mem.bytesAsValue(ReceivedFullEncryptedMessage, &full_message_bytes).*;

    const encryption_pubkey = if (std.mem.eql(u8, &pubkey, &full_message.from)) full_message.data.target_id else full_message.from;

    const dm_id_hex = std.fmt.bytesToHex(encryption_pubkey, .lower);

    const other_pubkey = std.crypto.ecc.Curve25519.fromBytes(encryption_pubkey);

    const symmetric_key = try @import("../../client.zig").get_symmetric_key(other_pubkey, privkey);

    const decrypted_raw = try full_message.data.decrypt(symmetric_key);

    var decrypted: EncryptedPart = std.mem.bytesAsValue(EncryptedPart, &decrypted_raw).*;

    const msg_id = std.mem.readInt(u64, &decrypted.msg_id, .big);

    const is_from_me = std.mem.eql(u8, &full_message.from, &pubkey);

    const is_from_me_to_me = is_from_me and std.mem.eql(u8, &full_message.data.target_id, &pubkey);

    switch (decrypted.action_kind) {
        .SendMessageRequest => {
            const smr: EncryptedPart.SendMessageRequest = std.mem.bytesAsValue(EncryptedPart.SendMessageRequest, &decrypted.data).*;

            try handle_request(is_from_me, is_from_me_to_me, msg_id, .{ .msg = smr }, symmetric_key, full_message.from, dm_id_hex);
        },
        .SendFileRequest => {
            const sfr: EncryptedPart.SendFileRequest = std.mem.bytesAsValue(EncryptedPart.SendFileRequest, &decrypted.data).*;

            try handle_request(is_from_me, is_from_me_to_me, msg_id, .{ .file = sfr }, symmetric_key, full_message.from, dm_id_hex);
        },
        .SendData => {
            const sd: EncryptedPart.SendData = std.mem.bytesAsValue(EncryptedPart.SendData, &decrypted.data).*;

            const index = std.mem.readInt(u32, &sd.index, .big);

            var is_file: bool = undefined;

            const total_size = blk: {
                const req = receive_requests.getPtr(msg_id).?;
                switch (req.data) {
                    .file => is_file = true,
                    .raw_message => is_file = false,
                }

                req.index += 1;

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

            {
                const value =
                    if (is_last) receive_requests.fetchRemove(msg_id).?.value else receive_requests.get(msg_id).?;

                const content = sd.payload_and_padding[0..payload_real_len];

                {
                    const total_received: f32 = @floatFromInt(@as(u64, index) * PAYLOAD_AND_PADDING_SIZE + content.len);
                    const avancement = total_received / @as(f32, @floatFromInt(total_size)) * 100;

                    switch (value.data) {
                        .file => |f| {
                            std.debug.print("Received {d:.2}% of the file `{s}`\n", .{ avancement, f.filename[0..f.filename_len] });
                        },
                        .raw_message => {
                            std.debug.print("Received {d:.2}% of the message\n", .{avancement});
                        },
                    }
                }

                //write
                switch (value.data) {
                    .file => |f| {
                        const encrypted_block = utils.encrypt_chacha(sd.payload_and_padding.len, &sd.payload_and_padding, symmetric_key);
                        try f.file.writeAll(&encrypted_block);
                    },
                    .raw_message => |rm| @memcpy(rm[@as(u64, index) * constants.PAYLOAD_AND_PADDING_SIZE .. @as(u64, index) * constants.PAYLOAD_AND_PADDING_SIZE + content.len], content),
                }

                if (is_last) {
                    const contentz = switch (value.data) {
                        .file => |f| try allocator.dupeZ(u8, f.filename[0..f.filename_len]),
                        .raw_message => |rm| try allocator.dupeZ(u8, rm),
                    };

                    const msg = @import("../gui/messages.zig").Message{
                        .sent_by = if (std.mem.eql(u8, &pubkey, &full_message.from)) .Me else .NotMe,
                        .is_file = is_file,
                        .content = contentz,
                    };

                    try GUI.handle_new_message(msg, encryption_pubkey);
                }
            }
        },
        .Accept => {
            if (is_from_me and !is_from_me_to_me) {
                const receive_req = unvalidated_receive_requests.fetchRemove(msg_id) orelse {
                    std.debug.print("Cannot find request {d} accepted by myself\n", .{msg_id});
                    return;
                };
                try receive_requests.put(msg_id, receive_req.value);
            } else {
                const entry = send_requests.fetchRemove(msg_id) orelse std.debug.panic("Invalid send request id {d}\n", .{decrypted.msg_id});

                switch (entry.value.data) {
                    .raw_message => |rm| std.debug.print("Accepted message request of size {d}o\n", .{rm.len}),
                    .file => |f| std.debug.print("Accepted file send request `{s}` of size {d}o\n", .{ f.name[0..f.name_len], f.size }),
                }

                _ = try std.Thread.spawn(.{}, @import("data.zig").send_data, .{ entry.value, msg_id });
            }
        },
        .Decline => {
            if (is_from_me) {
                _ = unvalidated_receive_requests.remove(msg_id);
                _ = receive_requests.remove(msg_id);
            } else {
                if (!send_requests.remove(msg_id)) {
                    std.log.err("Trying to delete invalid send request id {d}\n", .{msg_id});
                }
            }
        },
    }
}

const HandleRequestReqData = union(enum) { file: EncryptedPart.SendFileRequest, msg: EncryptedPart.SendMessageRequest };

fn handle_request(is_from_me: bool, is_from_me_to_me: bool, msg_id: u64, req_data: HandleRequestReqData, symmetric_key: [32]u8, target_id: [32]u8, dm_id_hex: [64]u8) !void {
    const total_size_bytes = switch (req_data) {
        .file => |f| f.total_size,
        .msg => |m| m.total_size,
    };

    const total_size = std.mem.readInt(u64, &total_size_bytes, .big);

    switch (req_data) {
        .file => |f| {
            //TODO ask the user to accept if the message/file is huge (e.g. > 100ko) or if the message is from a new entity
            //TODO but if the request is from myself, accept automatically
            std.debug.print("New file request : `{s}` of size {d}o\n", .{ f.filename[0..f.filename_len], total_size });
        },
        .msg => {
            std.debug.print("New message request of size {d}o\n", .{total_size});
        },
    }

    const receive_req_data: request.ReceiveRequestData = switch (req_data) {
        .file => |f| blk: {
            const cwd = std.fs.cwd();
            var dir = try utils.mkdir_if_absent(cwd, DECRYPTED_OUTPUT_DIR);
            defer dir.close();

            var dm_id_dir = try utils.mkdir_if_absent(dir, &dm_id_hex);
            defer dm_id_dir.close();

            const file = try dm_id_dir.createFile(f.filename[0..f.filename_len], .{});

            {
                const file_size_encrypted = utils.encrypt_chacha(8, &f.total_size, symmetric_key);

                try file.writeAll(&file_size_encrypted);
            }

            break :blk .{ .file = .{ .file = file, .filename = f.filename, .filename_len = f.filename_len } };
        },
        .msg => blk: {
            const out_message = try allocator.alloc(u8, total_size);

            break :blk .{ .raw_message = out_message };
        },
    };

    const rr = request.ReceiveRequest{
        .data = receive_req_data,
        .symmetric_key = symmetric_key,
        .target_id = target_id,
        .total_size = total_size,
        .index = 0,
    };

    // std.debug.print("ReceiveRequest symmetric key = {s}\n", .{std.fmt.bytesToHex(rr.symmetric_key, .lower)});

    if (is_from_me and !is_from_me_to_me) {
        const entry = try receive_requests.getOrPut(msg_id);
        if (entry.found_existing) @panic("no");

        entry.value_ptr.* = rr;
    } else {
        const entry = try unvalidated_receive_requests.getOrPut(msg_id);
        if (entry.found_existing) @panic("no");

        entry.value_ptr.* = rr;
    }
}

pub fn send_accept_or_decline(msg_id: u64, symmetric_key: [32]u8, target_id: [32]u8, is_accept: bool) !void {
    var padding: [ACTION_DATA_SIZE]u8 = undefined;
    std.crypto.random.bytes(&padding);

    switch (is_accept) {
        true => {
            const receive_req = unvalidated_receive_requests.fetchRemove(msg_id) orelse return;
            try receive_requests.put(msg_id, receive_req.value);
        },
        false => {
            _ = unvalidated_receive_requests.remove(msg_id);
        },
    }

    const action = if (is_accept) EncryptedPart.Action{ .Accept = .{ ._padding = padding } } else EncryptedPart.Action{ .Decline = .{ ._padding = padding } };

    const encrypted_part = EncryptedPart.init(msg_id, action);

    try send.send(symmetric_key, target_id, encrypted_part);
}
