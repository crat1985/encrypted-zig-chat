const std = @import("std");
const Int = @import("int.zig");
const Mutex = @import("../mutex.zig").Mutex;

pub const BLOCK_SIZE = 4000;
pub const FULL_MESSAGE_SIZE = BLOCK_SIZE + 60;
pub const ACTION_DATA_SIZE = BLOCK_SIZE - @sizeOf(EncryptedPart.ActionKind) - 8;
pub const PAYLOAD_AND_PADDING_SIZE = ACTION_DATA_SIZE - 4;

const allocator = std.heap.page_allocator;

const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

pub const ReceivedFullEncryptedMessage = extern struct {
    from: [32]u8,
    data: SentFullEncryptedMessage,

    const Self = @This();

    pub fn decode(full_part: [FULL_MESSAGE_SIZE + 32]u8) Self {
        return std.mem.bytesAsValue(Self, &full_part).*;
    }
};

pub const SentFullEncryptedMessage = extern struct {
    target_id: [32]u8,
    nonce: [12]u8,
    tag: [16]u8,
    encrypted: [BLOCK_SIZE]u8,

    comptime {
        std.debug.assert(@sizeOf(SentFullEncryptedMessage) == FULL_MESSAGE_SIZE);
    }

    const Self = @This();

    pub fn encrypt(symmetric_key: [32]u8, target_id: [32]u8, unencrypted: EncryptedPart) Self {
        var encrypted: [BLOCK_SIZE]u8 = undefined;

        const nonce = blk: {
            var nonce: [12]u8 = undefined;

            std.crypto.random.bytes(&nonce);

            break :blk nonce;
        };

        var tag: [ChaCha20Poly1305.tag_length]u8 = undefined;

        ChaCha20Poly1305.encrypt(&encrypted, &tag, unencrypted.encode(), &.{}, nonce, symmetric_key);

        return Self{
            .target_id = target_id,
            .nonce = nonce,
            .tag = tag,
            .encrypted = encrypted,
        };
    }

    pub fn encode(self: Self) [FULL_MESSAGE_SIZE]u8 {
        return std.mem.asBytes(&self).*;
    }

    pub fn decrypt(self: Self, symmetric_key: [32]u8) ![BLOCK_SIZE]u8 {
        var decrypted: [BLOCK_SIZE]u8 = undefined;

        try ChaCha20Poly1305.decrypt(&decrypted, &self.encrypted, self.tag, &.{}, self.nonce, symmetric_key);

        return decrypted;
    }

    pub fn decode(full_part: [FULL_MESSAGE_SIZE]u8) Self {
        return std.mem.bytesAsValue(Self, full_part).*;
    }
};

pub const ReceivedMessage = struct {
    from: [32]u8,
    to: [32]u8,
    msg_id: u64,
    // payload_real_len: u64,
    action: EncryptedPart.Action,
};

pub const EncryptedPart = extern struct {
    action_kind: ActionKind,
    msg_id: [8]u8,
    data: [ACTION_DATA_SIZE]u8,

    comptime {
        std.debug.assert(@sizeOf(EncryptedPart) == BLOCK_SIZE);
    }

    const Self = @This();

    pub const ActionKind = enum(u8) {
        SendMessageRequest,
        SendFileRequest,
        Accept,
        Decline,
        ///Continue sending a file or a message
        SendData,
    };

    pub const SendMessageRequest = extern struct {
        total_size: [8]u8,
        _padding: [ACTION_DATA_SIZE - 8]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();

        pub fn encode(self: *const InnerSelf) [ACTION_DATA_SIZE]u8 {
            return std.mem.asBytes(self).*;
        }

        pub fn decode(data: *const [ACTION_DATA_SIZE]u8) InnerSelf {
            return std.mem.bytesAsValue(InnerSelf, data).*;
        }
    };

    pub const SendFileRequest = extern struct {
        total_size: [8]u8,
        filename_len: u8,
        filename: [255]u8,
        _padding: [ACTION_DATA_SIZE - 8 - 1 - 255]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();

        pub fn encode(self: *const InnerSelf) [ACTION_DATA_SIZE]u8 {
            return std.mem.asBytes(self).*;
        }

        pub fn decode(data: *const [ACTION_DATA_SIZE]u8) InnerSelf {
            return std.mem.bytesAsValue(InnerSelf, data).*;
        }
    };

    pub const AcceptOrDecline = extern struct {
        _padding: [ACTION_DATA_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();

        pub fn encode(self: *const InnerSelf) [ACTION_DATA_SIZE]u8 {
            return self._padding;
        }

        pub fn decode(data: *const [ACTION_DATA_SIZE]u8) InnerSelf {
            return InnerSelf{
                ._padding = data.*,
            };
        }
    };

    pub const SendData = extern struct {
        index: [4]u8,
        payload_and_padding: [PAYLOAD_AND_PADDING_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();

        pub fn encode(self: *const InnerSelf) [ACTION_DATA_SIZE]u8 {
            return std.mem.asBytes(self).*;
        }

        pub fn decode(data: *const [ACTION_DATA_SIZE]u8) InnerSelf {
            return std.mem.bytesAsValue(InnerSelf, data).*;
        }
    };

    pub const Action = union(enum) {
        SendMessageRequest: SendMessageRequest,
        SendFileRequest: SendFileRequest,
        Accept: AcceptOrDecline,
        Decline: AcceptOrDecline,
        ///Continue sending a file or a message
        SendData: SendData,

        pub fn encode(self: *const Action) [ACTION_DATA_SIZE]u8 {
            return switch (self.*) {
                .SendMessageRequest => |*sm| sm.encode(),
                .SendFileRequest => |*sf| sf.encode(),
                .Accept => |*a| a.encode(),
                .Decline => |*d| d.encode(),
                .SendData => |*sd| sd.encode(),
            };
        }
    };

    pub fn init(msg_id: u64, action: Action) Self {
        var msg_id_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &msg_id_bytes, msg_id, .big);

        return Self{
            .action_kind = switch (action) {
                .Accept => ActionKind.Accept,
                .Decline => ActionKind.Decline,
                .SendMessageRequest => ActionKind.SendMessageRequest,
                .SendFileRequest => ActionKind.SendFileRequest,
                .SendData => ActionKind.SendData,
            },
            .msg_id = msg_id_bytes,
            .data = action.encode(),
        };
    }

    pub fn encode(self: *const Self) *const [BLOCK_SIZE]u8 {
        return std.mem.asBytes(self);
    }

    pub fn decode(data: *[BLOCK_SIZE]u8) *Self {
        return std.mem.bytesAsValue(Self, data);
    }
};

pub fn send_request(writer: *Mutex(std.io.AnyWriter), symmetric_key: [32]u8, target_id: [32]u8, data: SendRequestData) !void {
    const msg_id = generate_msg_id();

    const raw_action_data =
        switch (data) {
            .file => |f| (EncryptedPart.SendFileRequest{
                .filename_len = f.name_len,
                .filename = f.name,
                .total_size = blk: {
                    const size = (try f.file.metadata()).size();
                    var size_bytes: [8]u8 = undefined;
                    std.mem.writeInt(u64, &size_bytes, size, .big);
                    break :blk size_bytes;
                },
                ._padding = blk: {
                    var padding: [ACTION_DATA_SIZE - 8 - 1 - 255]u8 = undefined;
                    std.crypto.random.bytes(&padding);
                    break :blk padding;
                },
            }).encode(),
            .raw_message => |m| (EncryptedPart.SendMessageRequest{
                .total_size = blk: {
                    const size = m.len;
                    var size_bytes: [8]u8 = undefined;
                    std.mem.writeInt(u64, &size_bytes, size, .big);
                    break :blk size_bytes;
                },
                ._padding = blk: {
                    var padding: [ACTION_DATA_SIZE - 8]u8 = undefined;
                    std.crypto.random.bytes(&padding);
                    break :blk padding;
                },
            }).encode(),
        };

    const encrypted_part = EncryptedPart{
        .action_kind = switch (data) {
            .file => .SendFileRequest,
            .raw_message => .SendMessageRequest,
        },
        .msg_id = blk: {
            var id: [8]u8 = undefined;
            std.mem.writeInt(u64, &id, msg_id, .big);
            break :blk id;
        },
        .data = raw_action_data,
    };

    const full_message = SentFullEncryptedMessage.encrypt(symmetric_key, target_id, encrypted_part).encode();

    {
        const entry = try send_requests.getOrPut(msg_id);
        if (entry.found_existing) std.debug.panic("Dupplicate message id generated (should not happen) : `{d}`", .{msg_id});

        entry.value_ptr.* = SendRequest{
            .data = data,
            .symmetric_key = symmetric_key,
            .target_id = target_id,
        };
    }

    const lock = writer.lock();
    defer writer.unlock();

    try lock.writeAll(&full_message);
}

pub fn send_full_message(writer: Mutex(std.io.AnyWriter), symmetric_key: [32]u8, target_id: [32]u8, raw_msg: []const u8) !void {
    const parts_count = (raw_msg.len + (PAYLOAD_AND_PADDING_SIZE - 1)) / PAYLOAD_AND_PADDING_SIZE;

    const msg_id = generate_msg_id();

    var total_size_bytes: [8]u8 = undefined;
    Int.writeInt(u64, raw_msg.len, &total_size_bytes, .big);

    for (0..parts_count) |i| {
        const beginning = i * PAYLOAD_AND_PADDING_SIZE;
        const end = if (i + 1 == parts_count) raw_msg.len else beginning + PAYLOAD_AND_PADDING_SIZE;

        var payload_and_padding: [PAYLOAD_AND_PADDING_SIZE]u8 = undefined;
        @memcpy(payload_and_padding[0 .. end - beginning], raw_msg[beginning..end]);
        std.crypto.random.bytes(payload_and_padding[end - beginning ..]);

        var index_bytes: [4]u8 = undefined;
        Int.writeInt(u32, @intCast(i), &index_bytes, .big);

        const action = EncryptedPart.Action{
            .SendMessageRequest = .{
                .index = index_bytes,
                .total_size = total_size_bytes,
                .payload_and_padding = payload_and_padding,
            },
        };

        const msg = create_message_part(symmetric_key, target_id, action, msg_id);

        const lock = writer.lock();
        defer writer.unlock();
        try lock.writeAll(&msg);
    }
}

pub fn create_message_part(symmetric_key: [32]u8, target_id: [32]u8, action: EncryptedPart.SendData, msg_id: u64) [FULL_MESSAGE_SIZE]u8 {
    var msg_id_bytes: [8]u8 = undefined;
    Int.writeInt(u64, msg_id, &msg_id_bytes, .big);

    const encrypted_part = EncryptedPart{
        .action_kind = .SendData,
        .msg_id = msg_id_bytes,
        .data = action.encode(),
    };

    const full_msg = SentFullEncryptedMessage.encrypt(symmetric_key, target_id, encrypted_part);

    return full_msg.encode();
}

pub fn generate_msg_id() u64 {
    const t: u64 = @as(u32, @bitCast(@as(i32, @truncate(std.time.timestamp()))));
    const rand = std.crypto.random.int(u32);
    return (t << 33) | rand;
}

pub fn decrypt_message(pubkey: *const [32]u8, privkey: [32]u8, reader: std.io.AnyReader) !ReceivedMessage {
    const full_message = ReceivedFullEncryptedMessage.decode(try reader.readBytesNoEof(FULL_MESSAGE_SIZE + 32));

    const encryption_pubkey = if (std.mem.eql(u8, pubkey, &full_message.from)) full_message.data.target_id else full_message.from;

    const other_pubkey = std.crypto.ecc.Curve25519.fromBytes(encryption_pubkey);

    const symmetric_key = try @import("../client.zig").get_symmetric_key(other_pubkey, privkey);

    var decrypted = try full_message.data.decrypt(symmetric_key);

    var decrypted_parsed = EncryptedPart.decode(&decrypted);

    const msg_id = std.mem.readInt(u64, &decrypted_parsed.msg_id, .big);

    switch (decrypted_parsed.action_kind) {
        .SendMessageRequest => {
            const encrypted_data = EncryptedPart.SendMessageRequest.decode(&decrypted_parsed.data);

            const total_size = std.mem.readInt(u64, &encrypted_data.total_size, .big);

            std.debug.print("Send message request :\n- msg_id = {d}\n- Total size = {d}\n", .{ msg_id, total_size });

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                // .payload_real_len = 0,
                .action = .{ .SendMessageRequest = .{ .total_size = encrypted_data.total_size, ._padding = encrypted_data._padding } },
            };
        },
        .SendData => {
            const encrypted_part = EncryptedPart.SendData.decode(&decrypted_parsed.data);

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                .action = .{ .SendData = .{ .index = encrypted_part.index, .payload_and_padding = encrypted_part.payload_and_padding } },
            };
        },
        .SendFileRequest => {
            const encrypted_part = EncryptedPart.SendFileRequest.decode(&decrypted_parsed.data);

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                // .payload_real_len = 0,
                .action = .{ .SendFileRequest = .{ .filename_len = encrypted_part.filename_len, .filename = encrypted_part.filename, .total_size = encrypted_part.total_size, ._padding = encrypted_part._padding } },
            };
        },
        .Accept => {
            const encrypted_part = EncryptedPart.AcceptOrDecline.decode(&decrypted_parsed.data);

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                // .payload_real_len = 0,
                .action = .{ .Accept = .{ ._padding = encrypted_part._padding } },
            };
        },
        .Decline => {
            const encrypted_part = EncryptedPart.AcceptOrDecline.decode(&decrypted_parsed.data);

            return ReceivedMessage{
                .from = full_message.from,
                .to = full_message.data.target_id,
                .msg_id = msg_id,
                // .payload_real_len = 0,
                .action = .{ .Decline = .{ ._padding = encrypted_part._padding } },
            };
        },
    }
}

pub const SendRequestData = union(enum) {
    raw_message: []const u8,
    file: struct {
        file: std.fs.File,
        name_len: u8,
        name: [255]u8,
    },
};

pub const SendRequest = struct {
    data: SendRequestData,
    symmetric_key: [32]u8,
    target_id: [32]u8,

    const Self = @This();

    pub fn make(self: Self, writer: *Mutex(std.io.AnyWriter), msg_id: u64) !void {
        var file_name: ?[]const u8 = undefined;

        const reader = switch (self.data) {
            .file => |f| blk: {
                file_name = f.name[0..f.name_len];
                break :blk f.file.reader().any();
            },
            .raw_message => |msg| blk: {
                file_name = null;
                const str = struct {
                    index: usize = 0,
                    data: []const u8,

                    const InnerSelf = @This();

                    pub fn read(s: *InnerSelf, buffer: []u8) anyerror!usize {
                        const n = @min(s.data[s.index..].len, buffer.len);

                        @memcpy(buffer[0..n], s.data[s.index .. s.index + n]);

                        s.index += n;

                        return n;
                    }
                };

                //TODO find better name
                var truc = str{ .data = msg };

                break :blk (std.io.Reader(*str, anyerror, str.read){ .context = &truc }).any();
            },
        };

        const total_size = switch (self.data) {
            .file => |f| (try f.file.metadata()).size(),
            .raw_message => |rm| rm.len,
        };

        const parts_count = (total_size + (PAYLOAD_AND_PADDING_SIZE - 1)) / PAYLOAD_AND_PADDING_SIZE;

        var data: [PAYLOAD_AND_PADDING_SIZE]u8 = undefined;

        for (0..parts_count) |i| {
            const n = try reader.readAll(&data);

            // std.debug.print("data = {s}\n", .{data[0..n]});

            std.crypto.random.bytes(data[n..]); //add padding if necessary

            var index: [4]u8 = undefined;
            std.mem.writeInt(u32, &index, @intCast(i), .big);

            const full_part = create_message_part(self.symmetric_key, self.target_id, .{ .index = index, .payload_and_padding = data }, msg_id);

            {
                const lock = writer.lock();
                defer writer.unlock();

                try lock.writeAll(&full_part);
            }

            {
                const total_sent: f32 = @floatFromInt(i * PAYLOAD_AND_PADDING_SIZE + n);
                const avancement = total_sent / @as(f32, @floatFromInt(total_size)) * 100;
                if (file_name) |name| {
                    std.debug.print("Sent {d:.2}% of the file `{s}`\n", .{ avancement, name });
                } else {
                    std.debug.print("Sent {d:.2}% of the message\n", .{avancement});
                }
            }

            if (n < PAYLOAD_AND_PADDING_SIZE) break;
        }
    }
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
