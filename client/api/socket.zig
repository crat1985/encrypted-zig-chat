const std = @import("std");
const Mutex = @import("../../mutex.zig").Mutex;

pub var _stream: std.net.Stream = undefined;
pub var writer: Mutex(std.io.AnyWriter) = undefined;
pub var reader: Mutex(std.io.AnyReader) = undefined;

pub fn init(s: std.net.Stream) void {
    _stream = s;
    writer = Mutex(std.io.AnyWriter).init(_stream.writer().any());
    reader = Mutex(std.io.AnyReader).init(_stream.reader().any());
}

pub fn deinit() void {
    _stream.close();
}
