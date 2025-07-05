const std = @import("std");

pub fn Mutex(comptime T: type) type {
    return struct {
        _data: T,
        inner_mutex: std.Thread.Mutex,

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{
                ._data = data,
                .inner_mutex = .{},
            };
        }

        pub fn lock(self: *Self) *T {
            self.inner_mutex.lock();

            return &self._data;
        }

        pub fn unlock(self: *Self) void {
            self.inner_mutex.unlock();
        }
    };
}
