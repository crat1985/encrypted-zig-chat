const std = @import("std");
const Mutex = @import("mutex.zig").Mutex;

fn handle_serv(s: std.net.Server) !void {
    var serv_mut = s;

    var out: [10000]u8 = undefined;
    while (true) {
        const conn = try serv_mut.accept();
        _ = try conn.stream.read(&out);
    }
}

var stream: std.net.Stream = undefined;
var w: Mutex(std.io.AnyWriter) = undefined;
var r: Mutex(std.io.AnyReader) = undefined;

test {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    {
        const serv = try addr.listen(.{
            .reuse_address = true,
            .reuse_port = true,
        });

        _ = try std.Thread.spawn(.{}, handle_serv, .{serv});
    }

    {
        const s = try std.net.tcpConnectToAddress(addr);
        stream = s;
        w = Mutex(std.io.AnyWriter).init(s.writer().any());
        r = Mutex(std.io.AnyReader).init(s.reader().any());
    }

    const w_lock = w.lock();
    defer w_lock.unlock();

    try w_lock.data.writeAll("test");
}
