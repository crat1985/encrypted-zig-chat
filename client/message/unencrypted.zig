const std = @import("std");

const constants = @import("../api/constants.zig");
const BLOCK_SIZE = constants.BLOCK_SIZE;
const FULL_MESSAGE_SIZE = constants.FULL_MESSAGE_SIZE;
const ChaCha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;
const EncryptedPart = @import("encrypted.zig").EncryptedPart;

pub const ReceivedFullEncryptedMessage = extern struct {
    from: [32]u8,
    data: SentFullEncryptedMessage,
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

        ChaCha20Poly1305.encrypt(&encrypted, &tag, std.mem.asBytes(&unencrypted), &.{}, nonce, symmetric_key);

        // std.debug.print("Tag = {s}, Nonce = {s}, Symmetric key = {s}\n", .{ std.fmt.bytesToHex(tag, .lower), std.fmt.bytesToHex(nonce, .lower), std.fmt.bytesToHex(symmetric_key, .lower) });

        return Self{
            .target_id = target_id,
            .nonce = nonce,
            .tag = tag,
            .encrypted = encrypted,
        };
    }

    pub fn decrypt(self: Self, symmetric_key: [32]u8) ![BLOCK_SIZE]u8 {
        var decrypted: [BLOCK_SIZE]u8 = undefined;

        // std.debug.print("Tag = {s}, Nonce = {s}, Symmetric key = {s}\n", .{ std.fmt.bytesToHex(self.tag, .lower), std.fmt.bytesToHex(self.nonce, .lower), std.fmt.bytesToHex(symmetric_key, .lower) });

        try ChaCha20Poly1305.decrypt(&decrypted, &self.encrypted, self.tag, &.{}, self.nonce, symmetric_key);

        return decrypted;
    }
};
