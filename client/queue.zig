const Mutex = @import("../mutex.zig").Mutex;
const std = @import("std");

pub const Queue = struct {
    data: Mutex([][]u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const data = allocator.alloc([]u8, 0) catch unreachable;

        return .{
            .data = Mutex([][]u8).init(data),
            .allocator = allocator,
        };
    }

    pub fn append(self: *Self, data: []u8) !void {
        const lock = self.data.lock();
        defer self.data.unlock();

        const new_slice = try self.allocator.alloc([]u8, lock.len + 1);
        @memcpy(new_slice[0..lock.len], lock.*);
        new_slice[new_slice.len - 1] = data;
        self.allocator.free(lock.*);

        lock.* = new_slice;
    }

    pub fn next(self: *Self) ![]u8 {
        const data_lock = while (true) {
            const lock = self.data.lock();

            if (lock.len != 0) break lock;

            self.data.unlock();

            std.time.sleep(std.time.ns_per_ms * 50);
        }; //wait for data to be added
        defer self.data.unlock();

        const data = data_lock.*[0];

        const new_slice = try self.allocator.alloc([]u8, data_lock.len - 1);
        @memcpy(new_slice, data_lock.*[1..]);
        self.allocator.free(data_lock.*);

        data_lock.* = new_slice;

        return data;
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data._data);
    }
};
