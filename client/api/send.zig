const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;
const SentFullEncryptedMessage = @import("../message/unencrypted.zig").SentFullEncryptedMessage;
const socket = @import("socket.zig");
const std = @import("std");
const constants = @import("constants.zig");

pub fn send(symmetric_key: [32]u8, target_id: [32]u8, encrypted_part: EncryptedPart) !void {
    const full_message = SentFullEncryptedMessage.encrypt(symmetric_key, target_id, encrypted_part);

    const lock = socket.lock_writer();
    defer lock.unlock();

    const full_message_bytes = std.mem.asBytes(&full_message);

    std.debug.print("UNECRYPTED DATA = {s}\n", .{std.fmt.bytesToHex(full_message_bytes[0 .. constants.FULL_MESSAGE_SIZE - constants.BLOCK_SIZE], .lower)});

    try lock.data.writeAll(full_message_bytes);
}
