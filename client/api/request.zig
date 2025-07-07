const std = @import("std");
const utils = @import("utils.zig");
const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;
const constants = @import("constants.zig");
const ACTION_DATA_SIZE = constants.ACTION_DATA_SIZE;
const PAYLOAD_AND_PADDING_SIZE = constants.PAYLOAD_AND_PADDING_SIZE;

const SentFullEncryptedMessage = @import("../message/unencrypted.zig").SentFullEncryptedMessage;
const socket = @import("socket.zig");
const Int = @import("../int.zig");

pub fn send_request(message_req: SendRequest) !void {
    const msg_id = utils.generate_msg_id();

    const raw_action_data =
        switch (message_req.data) {
            .file => |f| (EncryptedPart.SendFileRequest{
                .filename_len = f.name_len,
                .filename = f.name,
                .total_size = Int.intToBytes(u64, f.size, .big),
                ._padding = blk: {
                    var padding: [ACTION_DATA_SIZE - 8 - 1 - 255]u8 = undefined;
                    std.crypto.random.bytes(&padding);
                    break :blk padding;
                },
            }).encode(),
            .raw_message => |m| (EncryptedPart.SendMessageRequest{
                .total_size = Int.intToBytes(u64, m.len, .big),
                ._padding = blk: {
                    var padding: [ACTION_DATA_SIZE - 8]u8 = undefined;
                    std.crypto.random.bytes(&padding);
                    break :blk padding;
                },
            }).encode(),
        };

    const encrypted_part = EncryptedPart{
        .action_kind = switch (message_req.data) {
            .file => .SendFileRequest,
            .raw_message => .SendMessageRequest,
        },
        .msg_id = Int.intToBytes(u64, msg_id, .big),
        .data = raw_action_data,
    };

    const full_message = SentFullEncryptedMessage.encrypt(message_req.symmetric_key, message_req.target_id, encrypted_part);

    {
        const entry = try send_requests.getOrPut(msg_id);
        if (entry.found_existing) std.debug.panic("Dupplicate message id generated (should not happen) : `{d}`", .{msg_id});

        entry.value_ptr.* = message_req;
    }

    const lock = socket.lock_writer();
    defer lock.unlock();

    try lock.data.writeAll(std.mem.asBytes(&full_message));
}

pub const SendRequestData = union(enum) {
    raw_message: []const u8,
    file: struct {
        file: std.fs.File,
        name_len: u8,
        name: [255]u8,
        size: u64,
    },

    const Self = @This();

    pub fn total_size(self: Self) u64 {
        switch (self) {
            .raw_message => |msg| return msg.len,
            .file => |f| return f.size,
        }
    }
};

pub const SendRequest = struct {
    data: SendRequestData,
    symmetric_key: [32]u8,
    target_id: [32]u8,
};

pub var send_requests: std.AutoHashMap(u64, SendRequest) = undefined;

pub const ReceiveRequestData = union(enum) {
    raw_message: []u8,
    file: struct { file: std.fs.File, filename: [255]u8, filename_len: u8 },
};

pub const ReceiveRequest = struct {
    data: ReceiveRequestData,
    symmetric_key: [32]u8,
    target_id: [32]u8,
    total_size: u64,
};

pub var receive_requests: std.AutoHashMap(u64, ReceiveRequest) = undefined;
