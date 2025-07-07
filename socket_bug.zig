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

pub var _file: std.fs.File = undefined;
pub var writer: Mutex(std.io.AnyWriter) = undefined;
pub var reader: Mutex(std.io.AnyReader) = undefined;

test {
    {
        const f = try std.fs.cwd().createFile("zgopzjpogjzepogjzepojgzeoppojopgjzeopgj.txt", .{});
        init(f);
    }

    defer _file.close();

    const w_lock = writer.lock();
    defer w_lock.unlock();

    try w_lock.data.writeAll("test");
}

pub fn init(file: std.fs.File) void {
    _file = file;
    writer = Mutex(std.io.AnyWriter).init(_file.writer().any());
    reader = Mutex(std.io.AnyReader).init(_file.reader().any());
}
