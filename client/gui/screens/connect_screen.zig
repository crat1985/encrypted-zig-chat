const std = @import("std");
const C = @import("c.zig").C;
const GUI = @import("../gui.zig");
const txt_input = @import("text_input.zig");
const Font = @import("font.zig");
const Button = @import("button.zig").Button;

const allocator = std.heap.page_allocator;

pub fn connect_to_server() !std.net.Stream {
    var server_addr = allocator.alloc(u8, 0) catch unreachable;
    var server: ?std.net.Stream = null;

    while (!C.WindowShouldClose() and server == null) {
        C.BeginDrawing();
        defer C.EndDrawing();

        C.ClearBackground(C.BLACK);

        GUI.WIDTH = @floatFromInt(C.GetScreenWidth());
        GUI.HEIGHT = @floatFromInt(C.GetScreenHeight());

        var cursor = C.MOUSE_CURSOR_DEFAULT;
        defer C.SetMouseCursor(cursor);

        const bounds = C.Rectangle{
            .x = 0,
            .y = 0,
            .width = GUI.WIDTH,
            .height = GUI.HEIGHT,
        };

        try draw_connect_to_server_screen(&server_addr, &server, bounds, &cursor);

        if (C.IsKeyPressed(C.KEY_ENTER)) {
            try connect_to_server_button_clicked(&server_addr, &server);
        }
    }

    if (C.WindowShouldClose()) std.process.exit(0);

    return server.?;
}

fn draw_connect_to_server_screen(server_addr: *[]u8, server: *?std.net.Stream, bounds: C.Rectangle, cursor: *c_int) !void {
    var txt_input_bounds = C.Rectangle{
        .x = bounds.x,
        .y = bounds.y + bounds.height / 6,
        .width = bounds.width,
        .height = bounds.height / 6,
    };

    const server_addr_input = txt_input.TextInput(u8).init(server_addr, txt_input_bounds, GUI.FONT_SIZE, .{ .x = .Center, .y = .Center }, .{ .x = .Center, .y = .Center }, null, C.DARKGRAY, C.WHITE, null);
    server_addr_input.draw(true);

    txt_input_bounds.y += txt_input_bounds.height;

    const ConnectButtonText = "Connect";

    const connect_button = Button(u8).init_default_text_button_center(txt_input_bounds, ConnectButtonText, true);
    connect_button.set_cursor(cursor);
    connect_button.draw();

    if (connect_button.is_clicked()) {
        try connect_to_server_button_clicked(server_addr, server);
    }
}

const DEFAULT_ADDR = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

fn connect_to_server_button_clicked(server_addr: *[]u8, server: *?std.net.Stream) !void {
    if (server_addr.len == 0) {
        server.* = std.net.tcpConnectToAddress(DEFAULT_ADDR) catch |err| return std.log.err("Error connecting to the server : {}", .{err});
        return;
    }

    var iterator = std.mem.splitScalar(u8, server_addr.*, ':');
    const host = iterator.next().?;
    const port: u16 = blk2: {
        const port = iterator.next() orelse break :blk2 8080;
        break :blk2 try std.fmt.parseInt(u16, port, 10);
    };
    std.log.info("Trying to connect to {s}:{d}...", .{ host, port });
    server.* = std.net.tcpConnectToHost(allocator, host, port) catch |err| return std.log.err("Error connecting to the server : {}", .{err});
}
