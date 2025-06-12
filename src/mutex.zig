const std = @import("std");

pub fn Mutex(comptime T: type) type {
    return struct {
        _data: T,
        owner: std.atomic.Value(u128),

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{
                ._data = data,
                .owner = std.atomic.Value(u128).init(0),
            };
        }

        fn get_thread_id() u128 {
            return (@as(u65, 0b1) << 64) | @as(u64, std.Thread.getCurrentId());
        }

        pub fn lock(self: *Self) *T {
            const thread_id = Self.get_thread_id();
            _ = self.owner.cmpxchgStrong(0, thread_id, .seq_cst, .seq_cst);

            return &self._data;
        }

        pub fn unlock(self: *Self) void {
            const thread_id = Self.get_thread_id();
            _ = self.owner.cmpxchgStrong(thread_id, 0, .seq_cst, .seq_cst);
        }
    };
}
