const std = @import("std");

/// buffer.len >= @sizeOf(T)
pub fn writeInt(comptime T: type, value: T, buffer: []u8, endian: std.builtin.Endian) void {
    var array: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &array, value, endian);
    @memcpy(buffer[0..array.len], &array);
}
