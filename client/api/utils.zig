const std = @import("std");

pub fn generate_msg_id() u64 {
    const t: u64 = @as(u32, @bitCast(@as(i32, @truncate(std.time.timestamp()))));
    const rand = std.crypto.random.int(u32);
    return (t << 33) | rand;
}
