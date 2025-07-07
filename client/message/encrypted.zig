const std = @import("std");

const Int = @import("../int.zig");
const constants = @import("../api/constants.zig");
const ACTION_DATA_SIZE = constants.ACTION_DATA_SIZE;
const BLOCK_SIZE = constants.BLOCK_SIZE;
const PAYLOAD_AND_PADDING_SIZE = constants.PAYLOAD_AND_PADDING_SIZE;

const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

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

        pub fn encode(s: InnerSelf) [ACTION_DATA_SIZE]u8 {
            return std.mem.asBytes(&s).*;
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

        pub fn encode(s: InnerSelf) [ACTION_DATA_SIZE]u8 {
            return std.mem.asBytes(&s).*;
        }
    };

    pub const AcceptOrDecline = extern struct {
        _padding: [ACTION_DATA_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();
    };

    pub const SendData = extern struct {
        index: [4]u8,
        payload_and_padding: [PAYLOAD_AND_PADDING_SIZE]u8,

        comptime {
            std.debug.assert(@sizeOf(InnerSelf) == ACTION_DATA_SIZE);
        }

        const InnerSelf = @This();
    };

    pub const Action = union(enum) {
        SendMessageRequest: SendMessageRequest,
        SendFileRequest: SendFileRequest,
        Accept: AcceptOrDecline,
        Decline: AcceptOrDecline,
        ///Continue sending a file or a message
        SendData: SendData,

        pub fn encode(self: *const Action) [ACTION_DATA_SIZE]u8 {
            const out: *const [ACTION_DATA_SIZE]u8 =
                switch (self.*) {
                    .SendMessageRequest => |*sm| @ptrCast(sm),
                    .SendFileRequest => |*sf| @ptrCast(sf),
                    .Accept => |*a| @ptrCast(a),
                    .Decline => |*d| @ptrCast(d),
                    .SendData => |*sd| @ptrCast(sd),
                };

            return out.*;
        }
    };

    pub fn init(msg_id: u64, action: Action) Self {
        return Self{
            .action_kind = switch (action) {
                .Accept => ActionKind.Accept,
                .Decline => ActionKind.Decline,
                .SendMessageRequest => ActionKind.SendMessageRequest,
                .SendFileRequest => ActionKind.SendFileRequest,
                .SendData => ActionKind.SendData,
            },
            .msg_id = Int.intToBytes(u64, msg_id, .big),
            .data = action.encode(),
        };
    }
};
