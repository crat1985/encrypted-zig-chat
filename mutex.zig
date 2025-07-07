const std = @import("std");

pub fn Mutex(comptime T: type) type {
    return struct {
        _data: T,
        inner_mutex: std.Thread.Mutex = .{},

        const Self = @This();

        pub const Guard = struct {
            data: *T,
            m: *std.Thread.Mutex,

            pub fn unlock(self: Guard) void {
                self.m.unlock();
            }
        };

        pub fn init(data: T) Self {
            return Self{
                ._data = data,
            };
        }

        pub fn lock(self: *Self) Guard {
            self.inner_mutex.lock();

            return Guard{
                .data = &self._data,
                .m = &self.inner_mutex,
            };
        }
    };
}
