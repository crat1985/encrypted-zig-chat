const std = @import("std");

pub fn Mutex(comptime T: type) type {
    return struct {
        _data: T,
        owner: std.atomic.Value(u64),

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{
                ._data = data,
                .owner = std.atomic.Value(u64).init(0),
            };
        }

        fn get_thread_id() u64 {
            return std.Thread.getCurrentId();
        }

        pub fn lock(self: *Self) *T {
            const thread_id = Self.get_thread_id();
            while (true) {
                const result = self.owner.cmpxchgStrong(0, thread_id, .seq_cst, .seq_cst);
                if (result) |_| break;
            }

            return &self._data;
        }

        pub fn unlock(self: *Self) void {
            const thread_id = Self.get_thread_id();
            while (true) {
                const result = self.owner.cmpxchgStrong(thread_id, 0, .seq_cst, .seq_cst);
                if (result) |_| break;
            }
        }
    };
}
