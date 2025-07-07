const std = @import("std");

pub fn openWithDefault(file_path: []const u8) !void {
    const allocator = std.heap.page_allocator;

    const target = @import("builtin").target;
    const args: []const []const u8 =
        if (target.os.tag == .windows) &.{ "cmd", "/c", "start", "", file_path } else if (target.os.tag == .macos) &.{ "open", file_path } else if (target.os.tag == .linux or target.os.tag == .freebsd) &.{ "xdg-open", file_path } else @compileError("Unsupported OS");

    var child = std.process.Child.init(args, allocator);
    try child.spawn();
    _ = try child.wait(); //remove if don't care about exit code ?
}
