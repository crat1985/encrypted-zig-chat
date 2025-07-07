const std = @import("std");

pub var lock_count: usize = 0;
pub var unlock_count: usize = 0;

pub fn Mutex(comptime T: type) type {
    return struct {
        _data: T,
        inner_mutex: std.Thread.Mutex = .{},

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{
                ._data = data,
            };
        }

        pub fn lock(self: *Self) *T {
            self.inner_mutex.lock();

            lock_count += 1;

            return &self._data;
        }

        pub fn unlock(self: *Self) void {
            self.inner_mutex.unlock();

            unlock_count += 1;
        }
    };
}
