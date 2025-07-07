const std = @import("std");

pub fn Guard(comptime T: type) type {
    return struct {
        data: *T,
        mutex: *std.Thread.Mutex,

        pub fn unlock(self: @This()) void {
            self.mutex.unlock();
        }
    };
}

var writer_mutex = std.Thread.Mutex{};

var writer: std.io.AnyWriter = undefined;

pub fn lock_writer() Guard(std.io.AnyWriter) {
    writer_mutex.lock();
    return Guard(std.io.AnyWriter){
        .data = &writer,
        .mutex = &writer_mutex,
    };
}

pub fn init(w: std.io.AnyWriter) void {
    writer = w;
}
