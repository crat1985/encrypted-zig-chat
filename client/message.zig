const std = @import("std");
const Int = @import("int.zig");

pub const BLOCK_SIZE = 4000;
pub const FULL_MESSAGE_SIZE = BLOCK_SIZE + 60;
const ACTION_DATA_SIZE = BLOCK_SIZE - @sizeOf(EncryptedPart.ActionKind) - 8;
const PAYLOAD_AND_PADDING_SIZE = ACTION_DATA_SIZE - 4 - 8;

const allocator = std.heap.page_allocator;

const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

pub const ReceivedFullEncryptedMessage = packed struct {
    from: [32]u8,
    data: SentFullEncryptedMessage,
};

pub const SentFullEncryptedMessage = packed struct {
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

        ChaCha20Poly1305.encrypt(&encrypted, &tag, &unencrypted.encode(), &.{}, nonce, symmetric_key);

        return Self{
            .target_id = target_id,
            .nonce = nonce,
            .tag = tag,
            .encrypted = encrypted,
        };
    }

    pub fn encode(self: Self) [BLOCK_SIZE]u8 {
        return std.mem.asBytes(&self).*;
    }

    pub fn decrypt(self: Self, symmetric_key: [32]u8) [BLOCK_SIZE]u8 {
        var decrypted: [BLOCK_SIZE]u8 = undefined;

        ChaCha20Poly1305.decrypt(&decrypted, &self.encrypted, self.tag, &.{}, self.nonce, symmetric_key);

        return decrypted;
    }

    pub fn decode(full_part: [FULL_MESSAGE_SIZE]u8) Self {
        return std.mem.bytesAsValue(Self, full_part).*;
    }
};

pub const EncryptedPart = packed struct {
    action_kind: ActionKind,
    msg_id: u64,
    data: [ACTION_DATA_SIZE]u8,

    const Self = @This();

    pub const ActionKind = enum(u8) {
        SendMessage,
        AcceptFile,
    };

    pub const SendMessageAction = struct {
        index: u32,
        total_size: u64,
        payload_and_padding: [PAYLOAD_AND_PADDING_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(EncryptedPart) == BLOCK_SIZE);
        }

        const InnerSelf = @This();

        pub fn encode(self: InnerSelf) [ACTION_DATA_SIZE]u8 {
            var action_data: [ACTION_DATA_SIZE]u8 = undefined;
            Int.writeInt(u32, self.index, action_data[0..4], .big);

            Int.writeInt(u64, self.total_size, action_data[4 .. 4 + 8], .big);

            @memcpy(action_data[4 + 8 ..], &self.payload_and_padding);

            return action_data;
        }
    };

    pub const AcceptFileAction = struct {
        _padding: [ACTION_DATA_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(EncryptedPart) == BLOCK_SIZE);
        }
    };

    pub const Action = packed union {
        SendMessage: SendMessageAction,
        AcceptFile: AcceptFileAction,

        pub fn encode(self: Action) [ACTION_DATA_SIZE]u8 {
            switch (self) {
                .SendMessage => |sm| sm.encode(),
                .AcceptFileAction => |af| std.mem.asBytes(&af._padding),
            }
        }
    };

    pub fn init(msg_id: u64, action: Action) Self {
        return Self{
            .action_kind = switch (action) {
                .AcceptFile => ActionKind.AcceptFile,
                .SendMessage => ActionKind.SendMessage,
            },
            .msg_id = msg_id,
            .data = action.encode(),
        };
    }

    pub fn encode(self: Self) [BLOCK_SIZE]u8 {
        var result: [BLOCK_SIZE]u8 = undefined;
        result[0] = @intFromEnum(self.action_kind);
        Int.writeInt(u64, self.msg_id, result[1 .. 1 + 8], .big);
        @memcpy(result[9..], &self.data);

        return result;
    }

    pub fn decode(data: [BLOCK_SIZE]u8) Self {
        const action_kind: ActionKind = @enumFromInt(data[0]);
        const msg_id = std.mem.readInt(u64, data[1..9], .big);
        var out_data: [ACTION_DATA_SIZE]u8 = undefined;
        @memcpy(&out_data, data[9..]);

        return Self{
            .action_kind = action_kind,
            .msg_id = msg_id,
            .data = out_data,
        };
    }
};

pub fn send_full_message(writer: std.io.AnyWriter, symmetric_key: [32]u8, target_id: [32]u8, action: EncryptedPart.Action) !void {
    const parts_count = (raw_msg.len + (PAYLOAD_AND_PADDING_SIZE - 1)) / PAYLOAD_AND_PADDING_SIZE;

    const msg_id = generate_msg_id();

    for (0..parts_count) |i| {
        const beginning = i * PAYLOAD_AND_PADDING_SIZE;
        const end = if (i + 1 == parts_count) raw_msg.len else beginning + PAYLOAD_AND_PADDING_SIZE;

        const msg = try create_message_part(symmetric_key, target_id, raw_msg[beginning..end], msg_id, @intCast(i), raw_msg.len);
        try writer.writeAll(&msg);
    }
}

pub fn create_message_part(symmetric_key: [32]u8, target_id: [32]u8, raw_msg: []const u8, msg_id: u64, index: u32, total_size: u64) ![4060]u8 {
    var entire_part: [FULL_MESSAGE_SIZE]u8 = undefined;

    var i: usize = 0;

    @memcpy(entire_part[i .. i + target_id.len], &target_id);
    i += target_id.len;

    @memcpy(entire_part[i .. i + nonce.len], &nonce);
    i += nonce.len;

    const unencrypted_part: [BLOCK_SIZE]u8 = undefined;
    {
        var j: usize = 0;
        Int.writeInt(u64, msg_id, unencrypted_part[j .. j + 8], .big);
        j += 8;

        Int.writeInt(u32, index, unencrypted_part[j .. j + 4], .big);
        j += 4;

        if (index == 0) {
            Int.writeInt(u64, total_size, unencrypted_part[j .. j + 8], .big);
            j += 8;
        }

        Int.writeInt(u64, raw_msg.len, unencrypted_part[0..8], .big);
        @memcpy(unencrypted_part[8 .. 8 + raw_msg.len], raw_msg);
        std.crypto.random.bytes(unencrypted_part[8 + raw_msg.len ..]);
    }

    @memcpy(entire_part[i .. i + tag.len], &tag);
    i += tag.len;
}

pub fn generate_msg_id() u64 {
    const t: u64 = @as(u32, @truncate(std.time.timestamp()));
    const rand = std.crypto.random.int(u32);
    return (t << 33) | rand;
}

/// * ~~Block count of the encrypted part (4 bytes) (clear)~~
/// * ~~From (32 bytes)~~
/// * ~~*DM ID (0 or 32 bytes) (only if `From` == me)*~~
/// * Nonce (12 bytes) (clear)
/// * Tag (16 bytes) (clear)
/// * Encrypted message
///     * Real size of the payload in bytes (8 bytes)
///     * Actual payload
///     * Padding
pub fn decrypt_message(block_count: u32, privkey: [32]u8, other_pubkey: std.crypto.ecc.Curve25519, reader: std.io.AnyReader) ![]u8 {
    const symmetric_key = try @import("../client.zig").get_symmetric_key(other_pubkey, privkey);

    const nonce = try reader.readBytesNoEof(12);
    const tag = try reader.readBytesNoEof(16);

    const total_encrypted_len = @as(u64, block_count) * BLOCK_SIZE;

    std.debug.print("Total encrypted length = {d}\n", .{total_encrypted_len});

    const encrypted = try allocator.alloc(u8, total_encrypted_len);
    defer allocator.free(encrypted);
    try reader.readNoEof(encrypted);

    const decrypted = try allocator.alloc(u8, total_encrypted_len);
    defer allocator.free(decrypted);
    try ChaCha20Poly1305.decrypt(decrypted, encrypted, tag, &.{}, nonce, symmetric_key);

    const payload_size = blk: {
        const payload_size_bytes = decrypted[0..8].*;
        break :blk std.mem.readInt(u64, &payload_size_bytes, .big);
    };

    const payload = try allocator.dupe(u8, decrypted[8 .. 8 + payload_size]);

    return payload;
}
