const std = @import("std");
const constants = @import("constants.zig");
const PAYLOAD_AND_PADDING_SIZE = constants.PAYLOAD_AND_PADDING_SIZE;
const FULL_MESSAGE_SIZE = constants.FULL_MESSAGE_SIZE;
const Int = @import("../int.zig");

const EncryptedPart = @import("../message/encrypted.zig").EncryptedPart;
const SentFullEncryptedMessage = @import("../message/unencrypted.zig").SentFullEncryptedMessage;
const socket = @import("socket.zig");
const SendRequest = @import("request.zig").SendRequest;

pub fn send_data(send_req: SendRequest, msg_id: u64) !void {
    const total_size = send_req.data.total_size();

    const parts_count = (total_size + (PAYLOAD_AND_PADDING_SIZE - 1)) / PAYLOAD_AND_PADDING_SIZE;

    for (0..parts_count) |i| {
        var payload_and_padding: [PAYLOAD_AND_PADDING_SIZE]u8 = undefined;
        const end = switch (send_req.data) {
            .file => |f| try f.file.readAll(&payload_and_padding),
            .raw_message => |m| blk: {
                const beginning = i * PAYLOAD_AND_PADDING_SIZE;
                const end = if (i + 1 == parts_count) total_size else beginning + PAYLOAD_AND_PADDING_SIZE;
                @memcpy(payload_and_padding[0 .. end - beginning], m[beginning..end]);

                break :blk end - beginning;
            },
        };
        std.crypto.random.bytes(payload_and_padding[end..]);

        const action = EncryptedPart.Action{ .SendData = .{ .index = Int.intToBytes(u32, @intCast(i), .big), .payload_and_padding = payload_and_padding } };

        const encrypted_part = EncryptedPart.init(msg_id, action);

        const full_msg = SentFullEncryptedMessage.encrypt(send_req.symmetric_key, send_req.target_id, encrypted_part);

        const lock = socket.writer.lock();
        defer lock.unlock();
        try lock.data.writeAll(std.mem.asBytes(&full_msg));

        {
            const total_sent: f32 = @floatFromInt(i * PAYLOAD_AND_PADDING_SIZE + end);
            const avancement = total_sent / @as(f32, @floatFromInt(total_size)) * 100;
            switch (send_req.data) {
                .file => |f| std.debug.print("Sent {d:.2}% of the file `{s}`\n", .{ avancement, f.name[0..f.name_len] }),
                .raw_message => std.debug.print("Sent {d:.2}% of the message\n", .{avancement}),
            }
        }
    }
}
